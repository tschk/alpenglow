#![allow(deprecated)]
use super::{PackageIndex, PackageMetadata};
use crate::error::{Result, OilError};
use flate2::read::GzDecoder;
use quick_xml::escape::unescape;
use quick_xml::events::Event;
use quick_xml::Reader;
use std::io::Read;
use std::time::{Duration, SystemTime};
use tracing::{debug, warn};

pub struct DnfRegistry {
    baseurl: String,
}

impl DnfRegistry {
    pub fn new(baseurl: &str) -> Self {
        Self {
            baseurl: baseurl.trim_end_matches('/').to_string(),
        }
    }

    pub fn fedora_default() -> Self {
        let version = fedora_version_id().unwrap_or_else(|| "43".to_string());
        let arch = rpm_arch().unwrap_or_else(|| "x86_64".to_string());
        Self::new(&format!(
            "https://dl.fedoraproject.org/pub/fedora/linux/releases/{version}/Everything/{arch}/os/"
        ))
    }

    pub fn default_for_host() -> Result<Self> {
        let os_release = std::fs::read_to_string("/etc/os-release").unwrap_or_default();
        if rpm_family_from_os_release(&os_release).as_deref() == Some("fedora") {
            return Ok(Self::fedora_default());
        }
        Err(OilError::PlatformNotSupported(
            "oil system registry install currently supports Fedora-compatible RPM repositories; this RPM distro needs repo-file parsing first".into(),
        ))
    }

    fn cache_path(&self) -> Result<std::path::PathBuf> {
        let dir = crate::ui::dirs::oil_cache_dir()?.join("system");
        std::fs::create_dir_all(&dir)?;
        let safe: String = self
            .baseurl
            .chars()
            .map(|c| if c.is_alphanumeric() { c } else { '-' })
            .collect();
        let short: String = safe
            .chars()
            .rev()
            .take(40)
            .collect::<String>()
            .chars()
            .rev()
            .collect();
        Ok(dir.join(format!("dnf-{}.json", short)))
    }

    fn is_cache_fresh(path: &std::path::Path) -> bool {
        if let Ok(meta) = std::fs::metadata(path) {
            if let Ok(modified) = meta.modified() {
                if let Ok(elapsed) = SystemTime::now().duration_since(modified) {
                    return elapsed < Duration::from_secs(24 * 3600);
                }
            }
        }
        false
    }

    pub async fn load(&self, client: &reqwest::Client) -> Result<PackageIndex> {
        let cache_path = self.cache_path()?;

        if Self::is_cache_fresh(&cache_path) {
            debug!("Loading DNF index from cache: {:?}", cache_path);
            let data = std::fs::read_to_string(&cache_path)?;
            let packages: Vec<PackageMetadata> = serde_json::from_str(&data)?;
            return Ok(PackageIndex { packages });
        }

        debug!("Fetching DNF repomd.xml from {}", self.baseurl);

        let repomd_url = format!("{}/repodata/repomd.xml", self.baseurl);
        let resp =
            client.get(&repomd_url).send().await.map_err(|e| {
                OilError::InstallError(format!("Failed to fetch repomd.xml: {}", e))
            })?;

        if !resp.status().is_success() {
            return Err(OilError::InstallError(format!(
                "Failed to fetch repomd.xml: HTTP {}",
                resp.status()
            )));
        }

        let repomd_xml = resp
            .text()
            .await
            .map_err(|e| OilError::InstallError(format!("Failed to read repomd.xml: {}", e)))?;

        let primary_location = find_primary_location(&repomd_xml).ok_or_else(|| {
            OilError::InstallError("Could not find primary.xml in repomd.xml".to_string())
        })?;

        let primary_url = format!("{}/{}", self.baseurl, primary_location);
        debug!("Fetching primary index: {}", primary_url);

        let resp =
            client.get(&primary_url).send().await.map_err(|e| {
                OilError::InstallError(format!("Failed to fetch primary.xml: {}", e))
            })?;

        if !resp.status().is_success() {
            return Err(OilError::InstallError(format!(
                "Failed to fetch primary index: HTTP {}",
                resp.status()
            )));
        }

        let bytes = resp
            .bytes()
            .await
            .map_err(|e| OilError::InstallError(format!("Failed to read primary index: {}", e)))?;

        let xml_content = if primary_location.ends_with(".gz") {
            let mut decoder = GzDecoder::new(&bytes[..]);
            let mut s = String::new();
            decoder.read_to_string(&mut s).map_err(|e| {
                OilError::InstallError(format!("Failed to decompress primary.xml.gz: {}", e))
            })?;
            s
        } else if primary_location.ends_with(".zst") {
            let mut decoder = zstd::Decoder::new(&bytes[..]).map_err(|e| {
                OilError::InstallError(format!("Failed to create zstd decoder: {}", e))
            })?;
            let mut s = String::new();
            decoder.read_to_string(&mut s).map_err(|e| {
                OilError::InstallError(format!("Failed to decompress primary.xml.zst: {}", e))
            })?;
            s
        } else {
            String::from_utf8(bytes.to_vec()).map_err(|e| {
                OilError::InstallError(format!("primary.xml is not valid UTF-8: {}", e))
            })?
        };

        let packages = parse_primary_xml(&xml_content, &self.baseurl)
            .map_err(|e| OilError::InstallError(format!("Failed to parse primary.xml: {}", e)))?;

        debug!("Parsed {} packages from DNF repo", packages.len());

        if packages.is_empty() {
            warn!("DNF index returned 0 packages — possible parse error");
        }

        let json = serde_json::to_string(&packages)?;
        std::fs::write(&cache_path, &json)?;

        Ok(PackageIndex { packages })
    }
}

fn fedora_version_id() -> Option<String> {
    let os_release = std::fs::read_to_string("/etc/os-release").ok()?;
    os_release.lines().find_map(|line| {
        let value = line.strip_prefix("VERSION_ID=")?;
        Some(value.trim_matches('"').to_string())
    })
}

fn rpm_arch() -> Option<String> {
    let output = std::process::Command::new("uname")
        .arg("-m")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let arch = String::from_utf8_lossy(&output.stdout).trim().to_string();
    match arch.as_str() {
        "amd64" => Some("x86_64".to_string()),
        "arm64" => Some("aarch64".to_string()),
        _ if !arch.is_empty() => Some(arch),
        _ => None,
    }
}

fn rpm_family_from_os_release(os_release: &str) -> Option<String> {
    let mut id = None;
    let mut like = Vec::new();
    for line in os_release.lines() {
        if let Some(value) = line.strip_prefix("ID=") {
            id = Some(value.trim_matches('"').to_ascii_lowercase());
        } else if let Some(value) = line.strip_prefix("ID_LIKE=") {
            like = value
                .trim_matches('"')
                .to_ascii_lowercase()
                .split_whitespace()
                .map(ToString::to_string)
                .collect();
        }
    }
    if id.as_deref() == Some("fedora") || like.iter().any(|token| token == "fedora") {
        Some("fedora".to_string())
    } else {
        id
    }
}

/// Helper to get local name of a quick-xml attribute key as an owned String.
fn attr_local_name(attr: &quick_xml::events::attributes::Attribute) -> String {
    let local = attr.key.local_name();
    std::str::from_utf8(local.as_ref())
        .unwrap_or("")
        .to_string()
}

fn find_primary_location(repomd_xml: &str) -> Option<String> {
    let mut reader = Reader::from_str(repomd_xml);
    let mut in_primary = false;
    let mut buf = Vec::new();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(ref e)) | Ok(Event::Empty(ref e)) => {
                let local_name = {
                    let local = e.local_name();
                    std::str::from_utf8(local.as_ref())
                        .unwrap_or("")
                        .to_string()
                };

                if local_name == "data" {
                    in_primary = false;
                    for attr in e.attributes().flatten() {
                        let key = attr_local_name(&attr);
                        let val = attr.unescape_value().unwrap_or_default();
                        if key == "type" && val.as_ref() == "primary" {
                            in_primary = true;
                        }
                    }
                }

                if in_primary && local_name == "location" {
                    for attr in e.attributes().flatten() {
                        let key = attr_local_name(&attr);
                        let val = attr.unescape_value().unwrap_or_default();
                        if key == "href" {
                            return Some(val.to_string());
                        }
                    }
                }
            }
            Ok(Event::End(ref e)) => {
                let local_name = {
                    let local = e.local_name();
                    std::str::from_utf8(local.as_ref())
                        .unwrap_or("")
                        .to_string()
                };
                if local_name == "data" {
                    in_primary = false;
                }
            }
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
        buf.clear();
    }

    None
}

fn parse_primary_xml(xml: &str, baseurl: &str) -> Result<Vec<PackageMetadata>> {
    let mut reader = Reader::from_str(xml);
    let mut packages = Vec::new();
    let mut buf = Vec::new();

    let mut in_package = false;
    let mut current_tag = String::new();

    let mut name = String::new();
    let mut version = String::new();
    let mut description = String::new();
    let mut location_href = String::new();
    let mut sha256: Option<String> = None;
    let mut installed_size: u64 = 0;
    let mut depends: Vec<String> = Vec::new();
    let mut provides: Vec<String> = Vec::new();
    let mut in_requires = false;
    let mut in_provides = false;
    let mut checksum_is_sha256 = false;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(ref e)) | Ok(Event::Empty(ref e)) => {
                let local_name = {
                    let local = e.local_name();
                    std::str::from_utf8(local.as_ref())
                        .unwrap_or("")
                        .to_string()
                };

                match local_name.as_str() {
                    "package" => {
                        let mut is_rpm = false;
                        for attr in e.attributes().flatten() {
                            let key = attr_local_name(&attr);
                            let val = attr.unescape_value().unwrap_or_default();
                            if key == "type" && val.as_ref() == "rpm" {
                                is_rpm = true;
                            }
                        }
                        if is_rpm {
                            in_package = true;
                            name = String::new();
                            version = String::new();
                            description = String::new();
                            location_href = String::new();
                            sha256 = None;
                            installed_size = 0;
                            depends = Vec::new();
                            provides = Vec::new();
                        }
                    }
                    "version" if in_package => {
                        let mut ver = String::new();
                        let mut rel = String::new();
                        for attr in e.attributes().flatten() {
                            let key = attr_local_name(&attr);
                            let val = attr.unescape_value().unwrap_or_default();
                            match key.as_str() {
                                "ver" => ver = val.to_string(),
                                "rel" => rel = val.to_string(),
                                _ => {}
                            }
                        }
                        if !rel.is_empty() {
                            version = format!("{}-{}", ver, rel);
                        } else {
                            version = ver;
                        }
                    }
                    "location" if in_package => {
                        for attr in e.attributes().flatten() {
                            let key = attr_local_name(&attr);
                            let val = attr.unescape_value().unwrap_or_default();
                            if key == "href" {
                                location_href = val.to_string();
                            }
                        }
                    }
                    "checksum" if in_package => {
                        checksum_is_sha256 = false;
                        for attr in e.attributes().flatten() {
                            let key = attr_local_name(&attr);
                            let val = attr.unescape_value().unwrap_or_default();
                            if key == "type" && val.as_ref() == "sha256" {
                                checksum_is_sha256 = true;
                            }
                        }
                        if checksum_is_sha256 {
                            current_tag = "checksum".to_string();
                        }
                    }
                    "size" if in_package => {
                        for attr in e.attributes().flatten() {
                            let key = attr_local_name(&attr);
                            let val = attr.unescape_value().unwrap_or_default();
                            if key == "installed" {
                                installed_size = val.parse().unwrap_or(0);
                            }
                        }
                    }
                    "requires" => in_requires = true,
                    "provides" => in_provides = true,
                    "entry" if in_package && in_requires => {
                        for attr in e.attributes().flatten() {
                            let key = attr_local_name(&attr);
                            let val = attr.unescape_value().unwrap_or_default();
                            if key == "name" {
                                let dname = val.as_ref();
                                if !dname.starts_with("rpmlib(") && !dname.is_empty() {
                                    depends.push(dname.to_string());
                                }
                            }
                        }
                    }
                    "entry" if in_package && in_provides => {
                        for attr in e.attributes().flatten() {
                            let key = attr_local_name(&attr);
                            let val = attr.unescape_value().unwrap_or_default();
                            if key == "name" && !val.is_empty() {
                                provides.push(val.to_string());
                            }
                        }
                    }
                    _ => {
                        if in_package {
                            current_tag = local_name;
                        }
                    }
                }
            }
            Ok(Event::Text(ref e)) if in_package => {
                let text = e
                    .decode()
                    .ok()
                    .and_then(|text| unescape(&text).ok().map(|text| text.into_owned()))
                    .unwrap_or_default();
                match current_tag.as_str() {
                    "name" => name = text,
                    "summary" if description.is_empty() => {
                        description = text;
                    }
                    "description" if description.is_empty() => {
                        description = text.lines().next().unwrap_or("").to_string();
                    }
                    "checksum" if checksum_is_sha256 => sha256 = Some(text),
                    _ => {}
                }
            }
            Ok(Event::End(ref e)) => {
                let local_name = {
                    let local = e.local_name();
                    std::str::from_utf8(local.as_ref())
                        .unwrap_or("")
                        .to_string()
                };
                match local_name.as_str() {
                    "package" if in_package => {
                        if !name.is_empty() && !version.is_empty() && !location_href.is_empty() {
                            let download_url = format!("{}/{}", baseurl, location_href);
                            packages.push(PackageMetadata {
                                name: name.clone(),
                                version: version.clone(),
                                description: description.clone(),
                                download_url,
                                sha256: sha256.clone(),
                                installed_size,
                                depends: depends.clone(),
                                provides: provides.clone(),
                            });
                        }
                        in_package = false;
                        current_tag = String::new();
                        checksum_is_sha256 = false;
                    }
                    "requires" => in_requires = false,
                    "provides" => in_provides = false,
                    _ => {
                        current_tag = String::new();
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => {
                warn!("XML parse error in primary.xml: {}", e);
                break;
            }
            _ => {}
        }
        buf.clear();
    }

    Ok(packages)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_primary_xml_captures_requires_and_provides() {
        let xml = r#"
            <metadata xmlns="http://linux.duke.edu/metadata/common"
                      xmlns:rpm="http://linux.duke.edu/metadata/rpm">
              <package type="rpm">
                <name>ripgrep</name>
                <arch>x86_64</arch>
                <version epoch="0" ver="14.1.1" rel="7.fc43"/>
                <checksum type="sha256">abc123</checksum>
                <summary>Line-oriented search tool</summary>
                <size installed="12345"/>
                <location href="Packages/r/ripgrep-14.1.1-7.fc43.x86_64.rpm"/>
                <format>
                  <rpm:requires>
                    <rpm:entry name="libc.so.6()(64bit)"/>
                    <rpm:entry name="rpmlib(CompressedFileNames)"/>
                  </rpm:requires>
                  <rpm:provides>
                    <rpm:entry name="rg"/>
                    <rpm:entry name="ripgrep"/>
                  </rpm:provides>
                </format>
              </package>
            </metadata>
        "#;

        let packages = parse_primary_xml(xml, "https://example.test/repo").unwrap();

        assert_eq!(packages.len(), 1);
        let pkg = &packages[0];
        assert_eq!(pkg.name, "ripgrep");
        assert_eq!(pkg.version, "14.1.1-7.fc43");
        assert_eq!(
            pkg.download_url,
            "https://example.test/repo/Packages/r/ripgrep-14.1.1-7.fc43.x86_64.rpm"
        );
        assert_eq!(pkg.sha256.as_deref(), Some("abc123"));
        assert_eq!(pkg.depends, vec!["libc.so.6()(64bit)"]);
        assert_eq!(pkg.provides, vec!["rg", "ripgrep"]);
    }

    #[test]
    fn rpm_family_detects_fedora_like_only() {
        assert_eq!(
            rpm_family_from_os_release("ID=ultramarine\nID_LIKE=\"fedora\"\n").as_deref(),
            Some("fedora")
        );
        assert_eq!(
            rpm_family_from_os_release("ID=rocky\nID_LIKE=\"rhel centos\"\n").as_deref(),
            Some("rocky")
        );
    }
}

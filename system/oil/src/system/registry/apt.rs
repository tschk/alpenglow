use super::{PackageIndex, PackageMetadata};
use crate::error::{Result, OilError};
use flate2::read::GzDecoder;
use sha2::Digest;
use std::collections::HashMap;
use std::io::Read;
use std::time::{Duration, SystemTime};
use tracing::{debug, warn};

pub struct AptRegistry {
    mirror: String,
    suite: String,
    components: Vec<String>,
    arch: String,
}

impl AptRegistry {
    #[allow(dead_code)]
    pub fn new(mirror: &str, suite: &str) -> Self {
        Self::new_with_components(mirror, suite, vec!["main".to_string()])
    }

    fn new_with_components(mirror: &str, suite: &str, components: Vec<String>) -> Self {
        let arch = std::env::consts::ARCH;
        let deb_arch = match arch {
            "x86_64" => "amd64",
            "aarch64" => "arm64",
            "arm" => "armhf",
            other => other,
        };
        Self {
            mirror: mirror.to_string(),
            suite: suite.to_string(),
            components,
            arch: deb_arch.to_string(),
        }
    }

    pub fn default_for_host() -> Self {
        match apt_family_from_os_release().as_deref() {
            Some("debian") => Self::debian_default(),
            _ => Self::ubuntu_default(),
        }
    }

    pub fn ubuntu_default() -> Self {
        let suite = debian_suite_from_os_release().unwrap_or_else(|| "noble".to_string());
        let mirror = match std::env::consts::ARCH {
            "x86_64" => "http://archive.ubuntu.com/ubuntu",
            _ => "http://ports.ubuntu.com/ubuntu-ports",
        };
        Self::new_with_components(
            mirror,
            &suite,
            vec![
                "main".to_string(),
                "restricted".to_string(),
                "universe".to_string(),
                "multiverse".to_string(),
            ],
        )
    }

    #[allow(dead_code)]
    pub fn debian_default() -> Self {
        let suite = debian_suite_from_os_release().unwrap_or_else(|| "bookworm".to_string());
        Self::new_with_components(
            "http://deb.debian.org/debian",
            &suite,
            vec![
                "main".to_string(),
                "contrib".to_string(),
                "non-free".to_string(),
                "non-free-firmware".to_string(),
            ],
        )
    }

    fn cache_path(&self) -> Result<std::path::PathBuf> {
        let dir = crate::ui::dirs::oil_cache_dir()?.join("system");
        std::fs::create_dir_all(&dir)?;
        Ok(dir.join(format!(
            "apt-{}-{}-{}-{}.json",
            cache_key(&self.mirror),
            cache_key(&self.suite),
            cache_key(&self.components.join(",")),
            cache_key(&self.arch)
        )))
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
            debug!("Loading APT index from cache: {:?}", cache_path);
            let data = std::fs::read_to_string(&cache_path)?;
            let packages: Vec<PackageMetadata> = serde_json::from_str(&data)?;
            return Ok(PackageIndex { packages });
        }

        debug!(
            "Fetching APT index for {} suite={} arch={}",
            self.mirror, self.suite, self.arch
        );

        // Fetch InRelease for hash chain verification
        let inrelease_url = format!("{}/dists/{}/InRelease", self.mirror, self.suite);
        debug!("Fetching InRelease from {}", inrelease_url);
        let inrelease_hashes = match client.get(&inrelease_url).send().await {
            Ok(resp) if resp.status().is_success() => {
                let bytes = resp.bytes().await.map_err(|e| {
                    OilError::InstallError(format!("Failed to read InRelease body: {}", e))
                })?;
                // Attempt GPG verification (best-effort, warn only)
                if let Err(e) = verify_gpg(&bytes).await {
                    warn!("GPG verification of InRelease failed: {}", e);
                }
                Some(parse_inrelease_hashes(&String::from_utf8_lossy(&bytes)))
            }
            Ok(resp) => {
                warn!(
                    "InRelease not available (HTTP {}), skipping hash verification",
                    resp.status()
                );
                None
            }
            Err(e) => {
                warn!(
                    "Could not fetch InRelease ({}), skipping hash verification",
                    e
                );
                None
            }
        };

        let mut all_packages: Vec<PackageMetadata> = Vec::new();

        for component in &self.components {
            let packages_gz_path = format!("{}/binary-{}/Packages.gz", component, self.arch);
            let url = format!("{}/dists/{}/{}", self.mirror, self.suite, packages_gz_path);
            debug!("Fetching {}", url);

            let resp = client.get(&url).send().await.map_err(|e| {
                OilError::InstallError(format!("Failed to fetch APT index from {}: {}", url, e))
            })?;

            if !resp.status().is_success() {
                warn!(
                    "APT index fetch failed for component {}: HTTP {}",
                    component,
                    resp.status()
                );
                continue;
            }

            let bytes = resp.bytes().await.map_err(|e| {
                OilError::InstallError(format!("Failed to read APT index body: {}", e))
            })?;

            // Verify SHA256 against InRelease if we have the hash
            if let Some(ref hashes) = inrelease_hashes {
                if let Some(expected) = hashes.get(&packages_gz_path) {
                    let mut hasher = sha2::Sha256::new();
                    hasher.update(&bytes);
                    let actual = hex::encode(hasher.finalize());
                    if actual != *expected {
                        return Err(OilError::ChecksumMismatch {
                            expected: expected.clone(),
                            actual,
                        });
                    }
                    debug!("SHA256 verified for {}", packages_gz_path);
                }
            }

            let mut decoder = GzDecoder::new(&bytes[..]);
            let mut decompressed = String::new();
            decoder.read_to_string(&mut decompressed).map_err(|e| {
                OilError::InstallError(format!("Failed to decompress APT Packages.gz: {}", e))
            })?;

            let pkgs = parse_packages_file(&decompressed, &self.mirror);
            debug!(
                "Parsed {} packages from {}/{}",
                pkgs.len(),
                self.suite,
                component
            );
            all_packages.extend(pkgs);
        }

        // Deduplicate by name, keeping first seen
        let mut seen = std::collections::HashSet::new();
        all_packages.retain(|p| seen.insert(p.name.clone()));

        let json = serde_json::to_string(&all_packages)?;
        std::fs::write(&cache_path, &json)?;

        Ok(PackageIndex {
            packages: all_packages,
        })
    }
}

fn cache_key(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect()
}

fn debian_suite_from_os_release() -> Option<String> {
    let os_release = std::fs::read_to_string("/etc/os-release").ok()?;
    suite_from_os_release(&os_release)
}

fn apt_family_from_os_release() -> Option<String> {
    let os_release = std::fs::read_to_string("/etc/os-release").ok()?;
    family_from_os_release(&os_release)
}

fn family_from_os_release(os_release: &str) -> Option<String> {
    let mut id = None;
    let mut id_like = Vec::new();

    for line in os_release.lines() {
        if let Some(value) = line.strip_prefix("ID=") {
            id = Some(value.trim_matches('"').to_string());
        } else if let Some(value) = line.strip_prefix("ID_LIKE=") {
            id_like = value
                .trim_matches('"')
                .split_whitespace()
                .map(ToString::to_string)
                .collect();
        }
    }

    if id.as_deref() == Some("debian") {
        return Some("debian".to_string());
    }
    if id.as_deref() == Some("ubuntu") || id_like.iter().any(|value| value == "ubuntu") {
        return Some("ubuntu".to_string());
    }
    if id_like.iter().any(|value| value == "debian") {
        return Some("debian".to_string());
    }
    id
}

fn suite_from_os_release(os_release: &str) -> Option<String> {
    let mut version_codename = None;
    let mut ubuntu_codename = None;

    for line in os_release.lines() {
        if let Some(value) = line.strip_prefix("VERSION_CODENAME=") {
            version_codename = Some(value.trim_matches('"').to_string());
        } else if let Some(value) = line.strip_prefix("UBUNTU_CODENAME=") {
            ubuntu_codename = Some(value.trim_matches('"').to_string());
        }
    }

    version_codename.or(ubuntu_codename)
}

/// Attempt GPG signature verification of InRelease content.
/// Returns Ok(()) if gpg is not available (graceful degradation).
/// Returns Err if gpg IS available and verification fails.
async fn verify_gpg(inrelease_bytes: &[u8]) -> Result<()> {
    use std::io::Write;
    use tempfile::NamedTempFile;

    // Write content to a temp file
    let mut tmp = NamedTempFile::new().map_err(|e| {
        OilError::InstallError(format!("Failed to create temp file for GPG: {}", e))
    })?;
    tmp.write_all(inrelease_bytes)
        .map_err(|e| OilError::InstallError(format!("Failed to write temp file for GPG: {}", e)))?;
    tmp.flush().ok();

    let path = tmp.path().to_path_buf();

    let output = match tokio::process::Command::new("gpg")
        .args(["--verify", &path.to_string_lossy()])
        .output()
        .await
    {
        Ok(o) => o,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            debug!("gpg not found, skipping InRelease signature verification");
            return Ok(());
        }
        Err(e) => {
            debug!(
                "gpg execution error ({}), skipping signature verification",
                e
            );
            return Ok(());
        }
    };

    if output.status.success() {
        debug!("GPG signature verification of InRelease succeeded");
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(OilError::InstallError(format!(
            "GPG signature verification of InRelease failed: {}",
            stderr.trim()
        )))
    }
}

/// Parse the SHA256 section from an InRelease file (PGP clearsigned).
/// Returns a map of relative path → SHA256 hash.
pub(crate) fn parse_inrelease_hashes(content: &str) -> HashMap<String, String> {
    let mut hashes = HashMap::new();

    // Strip PGP armor: content between the blank line after the armor header
    // and "-----BEGIN PGP SIGNATURE-----"
    let body = if let Some(start) = content.find("\n\n") {
        let after_header = &content[start + 2..];
        if let Some(sig_start) = after_header.find("-----BEGIN PGP SIGNATURE-----") {
            &after_header[..sig_start]
        } else {
            after_header
        }
    } else {
        content
    };

    let mut in_sha256 = false;
    for line in body.lines() {
        if line.starts_with("SHA256:") {
            in_sha256 = true;
            continue;
        }
        // Any non-indented line ends the SHA256 section
        if in_sha256 && !line.starts_with(' ') {
            in_sha256 = false;
        }
        if in_sha256 {
            // Format: " <hash>  <size>  <path>"
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 3 {
                let hash = parts[0].to_string();
                let path = parts[2].to_string();
                hashes.insert(path, hash);
            }
        }
    }

    hashes
}

pub(crate) fn parse_packages_file(content: &str, mirror: &str) -> Vec<PackageMetadata> {
    let mut packages = Vec::new();

    for stanza in content.split("\n\n") {
        let stanza = stanza.trim();
        if stanza.is_empty() {
            continue;
        }

        let mut name = String::new();
        let mut version = String::new();
        let mut description = String::new();
        let mut filename = String::new();
        let mut sha256: Option<String> = None;
        let mut installed_size: u64 = 0;
        let mut depends: Vec<String> = Vec::new();
        let mut provides: Vec<String> = Vec::new();

        let mut current_key = String::new();
        let mut current_val = String::new();

        let mut flush = |key: &str, val: &str| {
            let val = val.trim();
            match key {
                "Package" => name = val.to_string(),
                "Version" => version = val.to_string(),
                "Description" => description = val.lines().next().unwrap_or(val).to_string(),
                "Filename" => filename = val.to_string(),
                "SHA256" => sha256 = Some(val.to_string()),
                "Installed-Size" => {
                    installed_size = val.parse::<u64>().unwrap_or(0) * 1024;
                }
                "Depends" => {
                    for dep in val.split(',') {
                        let dep = dep.trim();
                        let alternatives: Vec<String> = dep
                            .split('|')
                            .map(|alt| super::parse_dep_name(alt.trim()).to_string())
                            .filter(|alt| !alt.is_empty())
                            .collect();
                        if !alternatives.is_empty() {
                            depends.push(alternatives.join(" | "));
                        }
                    }
                }
                "Provides" => {
                    for p in val.split(',') {
                        let pname = super::parse_dep_name(p.trim());
                        if !pname.is_empty() {
                            provides.push(pname.to_string());
                        }
                    }
                }
                _ => {}
            }
        };

        for line in stanza.lines() {
            if line.starts_with(' ') || line.starts_with('\t') {
                // Continuation line
                current_val.push('\n');
                current_val.push_str(line.trim_start());
            } else if let Some(colon_pos) = line.find(':') {
                // New field: flush current
                if !current_key.is_empty() {
                    flush(&current_key.clone(), &current_val.clone());
                }
                current_key = line[..colon_pos].trim().to_string();
                current_val = line[colon_pos + 1..].trim().to_string();
            }
        }
        if !current_key.is_empty() {
            flush(&current_key.clone(), &current_val.clone());
        }

        if name.is_empty() || version.is_empty() || filename.is_empty() {
            continue;
        }

        let download_url = format!("{}/{}", mirror, filename);

        packages.push(PackageMetadata {
            name,
            version,
            description,
            download_url,
            sha256,
            installed_size,
            depends,
            provides,
        });
    }

    packages
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_family_from_os_release_detects_debian() {
        let os_release = "ID=debian\nVERSION_CODENAME=bookworm\n";
        assert_eq!(
            family_from_os_release(os_release).as_deref(),
            Some("debian")
        );
    }

    #[test]
    fn test_family_from_os_release_detects_ubuntu_derivative() {
        let os_release = "ID=linuxmint\nID_LIKE=\"ubuntu debian\"\nUBUNTU_CODENAME=jammy\n";
        assert_eq!(
            family_from_os_release(os_release).as_deref(),
            Some("ubuntu")
        );
    }

    #[test]
    fn test_suite_from_os_release_prefers_version_codename() {
        let os_release = "ID=ubuntu\nVERSION_CODENAME=noble\nUBUNTU_CODENAME=jammy\n";
        assert_eq!(suite_from_os_release(os_release).as_deref(), Some("noble"));
    }

    #[test]
    fn test_suite_from_os_release_uses_ubuntu_codename() {
        let os_release = "ID=linuxmint\nUBUNTU_CODENAME=jammy\n";
        assert_eq!(suite_from_os_release(os_release).as_deref(), Some("jammy"));
    }

    #[test]
    fn test_parse_packages_file_basic() {
        let sample = r#"Package: curl
Version: 7.81.0-1ubuntu1.13
Architecture: amd64
Installed-Size: 411
Depends: libc6 (>= 2.17), libcurl4 (= 7.81.0-1ubuntu1.13), zlib1g (>= 1:1.1.4)
Filename: pool/main/c/curl/curl_7.81.0-1ubuntu1.13_amd64.deb
SHA256: abc123def456abc123def456abc123def456abc123def456abc123def456abc123
Description: command line tool for transferring data with URL syntax

Package: wget
Version: 1.21.2-2ubuntu1
Architecture: amd64
Installed-Size: 502
Depends: libc6 (>= 2.14), libpcre2-8-0 (>= 10.22)
Filename: pool/main/w/wget/wget_1.21.2-2ubuntu1_amd64.deb
SHA256: def456abc123def456abc123def456abc123def456abc123def456abc123def456
Description: retrieves files from the web

"#;
        let pkgs = parse_packages_file(sample, "http://archive.ubuntu.com/ubuntu");
        assert_eq!(pkgs.len(), 2);

        let curl = pkgs.iter().find(|p| p.name == "curl").unwrap();
        assert_eq!(curl.version, "7.81.0-1ubuntu1.13");
        assert_eq!(
            curl.sha256.as_deref(),
            Some("abc123def456abc123def456abc123def456abc123def456abc123def456abc123")
        );
        assert!(curl.depends.contains(&"libc6".to_string()));
        assert!(curl.depends.contains(&"libcurl4".to_string()));
        assert!(curl.depends.contains(&"zlib1g".to_string()));
        assert_eq!(
            curl.download_url,
            "http://archive.ubuntu.com/ubuntu/pool/main/c/curl/curl_7.81.0-1ubuntu1.13_amd64.deb"
        );

        let wget = pkgs.iter().find(|p| p.name == "wget").unwrap();
        assert_eq!(wget.version, "1.21.2-2ubuntu1");
    }

    #[test]
    fn test_parse_packages_multiline_description() {
        let sample = r#"Package: vim
Version: 2:8.2.3995-1ubuntu2.13
Installed-Size: 3741
Depends: vim-common (= 2:8.2.3995-1ubuntu2.13), vim-runtime (= 2:8.2.3995-1ubuntu2.13), libacl1 (>= 2.2.23)
Filename: pool/main/v/vim/vim_2.3995-1ubuntu2.13_amd64.deb
SHA256: aabbcc
Description: Vi IMproved - enhanced vi editor
 Vim is an almost compatible version of the UNIX editor vi.

"#;
        let pkgs = parse_packages_file(sample, "http://mirror.example.com");
        assert_eq!(pkgs.len(), 1);
        assert_eq!(pkgs[0].description, "Vi IMproved - enhanced vi editor");
    }

    #[test]
    fn test_parse_inrelease_hashes() {
        let inrelease = "-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\nOrigin: Ubuntu\nSuite: jammy\nSHA256:\n abc1111111111111111111111111111111111111111111111111111111111111111  12345  main/binary-amd64/Packages.gz\n def2222222222222222222222222222222222222222222222222222222222222222  67890  main/binary-amd64/Packages\n fed3333333333333333333333333333333333333333333333333333333333333333  11111  universe/binary-amd64/Packages.gz\n-----BEGIN PGP SIGNATURE-----\n\nfakeSignatureData\n-----END PGP SIGNATURE-----\n";
        let hashes = parse_inrelease_hashes(inrelease);
        assert_eq!(
            hashes
                .get("main/binary-amd64/Packages.gz")
                .map(|s| s.as_str()),
            Some("abc1111111111111111111111111111111111111111111111111111111111111111")
        );
        assert_eq!(
            hashes
                .get("universe/binary-amd64/Packages.gz")
                .map(|s| s.as_str()),
            Some("fed3333333333333333333333333333333333333333333333333333333333333333")
        );
        // Non-.gz variant should also be present (we store all hashes)
        assert!(hashes.contains_key("main/binary-amd64/Packages"));
    }
}

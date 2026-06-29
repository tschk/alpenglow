use super::{PackageIndex, PackageMetadata};
use crate::error::{OilError, Result};
use flate2::read::MultiGzDecoder;
use std::io::Read;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

pub struct ApkRegistry {
    mirror: String,
    branch: String,
    repos: Vec<String>,
    arch: String,
}

impl ApkRegistry {
    pub fn new(mirror: &str, branch: &str) -> Self {
        let arch = match std::env::consts::ARCH {
            "x86_64" => "x86_64",
            "aarch64" => "aarch64",
            "arm" => "armv7",
            other => other,
        };
        Self {
            mirror: mirror.to_string(),
            branch: branch.to_string(),
            repos: vec!["main".to_string(), "community".to_string()],
            arch: arch.to_string(),
        }
    }

    pub fn alpine_default() -> Self {
        let branch = alpine_branch_from_os_release().unwrap_or_else(|| "v3.20".to_string());
        Self::new("https://dl-cdn.alpinelinux.org/alpine", &branch)
    }

    fn cache_path(&self) -> Result<std::path::PathBuf> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| OilError::Install("$HOME not set".into()))?;
        let dir = home.join(".oil").join("cache").join("system");
        std::fs::create_dir_all(&dir)?;
        Ok(dir.join(format!(
            "apk-{}-{}-{}.json",
            cache_key(&self.mirror),
            cache_key(&self.branch),
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

    pub fn load(&self) -> Result<PackageIndex> {
        let cache_path = self.cache_path()?;

        if Self::is_cache_fresh(&cache_path) {
            let data = std::fs::read_to_string(&cache_path)?;
            let packages: Vec<PackageMetadata> = serde_json::from_str(&data)?;
            return Ok(PackageIndex::new(packages));
        }

        let mut all_packages: Vec<PackageMetadata> = Vec::new();

        for repo in &self.repos {
            let url = self.index_url(repo);
            eprintln!("Fetching APK index: {url}");

            let resp = ureq::get(&url).call().map_err(|e| {
                OilError::Install(format!("Failed to fetch APK index from {url}: {e}"))
            })?;

            let mut body = Vec::new();
            resp.into_body()
                .into_reader()
                .read_to_end(&mut body)
                .map_err(|e| OilError::Install(format!("Failed to read APK index body: {e}")))?;

            let pkgs = parse_apkindex_archive(&body, &self.mirror, &self.branch, repo, &self.arch)?;
            eprintln!(
                "Parsed {} packages from {}/{}",
                pkgs.len(),
                self.branch,
                repo
            );
            all_packages.extend(pkgs);
        }

        // Deduplicate
        let mut seen = std::collections::HashSet::new();
        all_packages.retain(|p| seen.insert(p.name.clone()));

        if let Some(parent) = cache_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&cache_path, &serde_json::to_string(&all_packages)?)?;

        Ok(PackageIndex::new(all_packages))
    }

    fn index_url(&self, repo: &str) -> String {
        format!(
            "{}/{}/{}/{}/APKINDEX.tar.gz",
            self.mirror, self.branch, repo, self.arch
        )
    }
}

fn cache_key(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect()
}

fn alpine_branch_from_os_release() -> Option<String> {
    let os_release = std::fs::read_to_string("/etc/os-release").ok()?;
    branch_from_os_release(&os_release)
}

fn branch_from_os_release(os_release: &str) -> Option<String> {
    let version = os_release.lines().find_map(|line| {
        let value = line.strip_prefix("VERSION_ID=")?;
        Some(value.trim_matches('"'))
    })?;
    let mut parts = version.split('.');
    let major = parts.next()?;
    let minor = parts.next()?;
    Some(format!("v{major}.{minor}"))
}

fn is_apkindex_entry(path: &std::path::Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| name == "APKINDEX")
        .unwrap_or(false)
}

fn parse_apkindex_archive(
    bytes: &[u8],
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Result<Vec<PackageMetadata>> {
    let mut decoder = MultiGzDecoder::new(bytes);
    let mut tar = Vec::new();
    decoder
        .read_to_end(&mut tar)
        .map_err(|e| OilError::Install(format!("Failed to decompress APKINDEX: {e}")))?;

    let mut offset = 0usize;
    while offset + 512 <= tar.len() {
        let header = &tar[offset..offset + 512];
        if header.iter().all(|byte| *byte == 0) {
            break;
        }

        let name = tar_header_string(&header[0..100]);
        let size = tar_header_size(&header[124..136])?;
        let data_start = offset + 512;
        let data_end = data_start
            .checked_add(size)
            .ok_or_else(|| OilError::Install("APKINDEX tar entry too large".into()))?;
        if data_end > tar.len() {
            return Err(OilError::Install("APKINDEX tar entry is truncated".into()));
        }

        if name
            .as_deref()
            .map(|n| is_apkindex_entry(std::path::Path::new(n)))
            .unwrap_or(false)
        {
            let content = std::str::from_utf8(&tar[data_start..data_end])
                .map_err(|e| OilError::Install(format!("APKINDEX is not UTF-8: {e}")))?;
            return Ok(parse_apkindex(content, mirror, branch, repo, arch));
        }

        offset = data_start + size.div_ceil(512) * 512;
    }

    Ok(Vec::new())
}

fn tar_header_string(bytes: &[u8]) -> Option<String> {
    let end = bytes
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(bytes.len());
    if end == 0 {
        return None;
    }
    Some(String::from_utf8_lossy(&bytes[..end]).to_string())
}

fn tar_header_size(bytes: &[u8]) -> Result<usize> {
    let text = String::from_utf8_lossy(bytes);
    let text = text.trim_matches(char::from(0)).trim();
    usize::from_str_radix(text, 8)
        .map_err(|e| OilError::Install(format!("invalid APKINDEX tar size: {e}")))
}

fn parse_apkindex(
    content: &str,
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Vec<PackageMetadata> {
    let mut packages = Vec::new();

    for stanza in content.split("\n\n") {
        let stanza = stanza.trim();
        if stanza.is_empty() {
            continue;
        }

        let mut name = String::new();
        let mut version = String::new();
        let mut description = String::new();
        let mut installed_size: u64 = 0;
        let mut depends: Vec<String> = Vec::new();
        let mut provides: Vec<String> = Vec::new();

        for line in stanza.lines() {
            if line.len() < 2 || line.as_bytes()[1] != b':' {
                continue;
            }
            let key = &line[..1];
            let val = line[2..].trim();

            match key {
                "P" => name = val.to_string(),
                "V" => version = val.to_string(),
                "T" => description = val.to_string(),
                "I" => installed_size = val.parse().unwrap_or(0),
                "D" => {
                    for dep in val.split_whitespace() {
                        let dname = super::parse_dep_name(dep);
                        if !dname.is_empty() && !dname.starts_with('!') {
                            depends.push(dname.to_string());
                        }
                    }
                }
                "p" => {
                    for prov in val.split_whitespace() {
                        let pname = super::parse_dep_name(prov);
                        if !pname.is_empty() {
                            provides.push(pname.to_string());
                        }
                    }
                }
                _ => {}
            }
        }

        if name.is_empty() || version.is_empty() {
            continue;
        }

        let url = format!("{mirror}/{branch}/{repo}/{arch}/{name}-{version}.apk");
        packages.push(PackageMetadata {
            name,
            version,
            description,
            download_url: url,
            sha256: None,
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
    fn test_branch_from_os_release_uses_major_minor() {
        let os_release = "ID=alpine\nVERSION_ID=3.20.3\n";
        assert_eq!(branch_from_os_release(os_release).as_deref(), Some("v3.20"));
    }

    #[test]
    fn test_branch_from_os_release_quoted_version() {
        let os_release = "ID=alpine\nVERSION_ID=\"3.21.0\"\n";
        assert_eq!(branch_from_os_release(os_release).as_deref(), Some("v3.21"));
    }

    #[test]
    fn test_branch_from_os_release_missing_version_id() {
        let os_release = "ID=alpine\n";
        assert_eq!(branch_from_os_release(os_release), None);
    }

    #[test]
    fn test_branch_from_os_release_missing_minor_version() {
        let os_release = "ID=alpine\nVERSION_ID=3\n";
        assert_eq!(branch_from_os_release(os_release), None);
    }

    #[test]
    fn test_branch_from_os_release_empty_string() {
        let os_release = "";
        assert_eq!(branch_from_os_release(os_release), None);
    }

    #[test]
    fn index_url_includes_architecture_segment() {
        let registry = ApkRegistry::new("https://dl-cdn.alpinelinux.org/alpine", "v3.24");
        let arch = match std::env::consts::ARCH {
            "x86_64" => "x86_64",
            "aarch64" => "aarch64",
            "arm" => "armv7",
            other => other,
        };
        assert_eq!(
            registry.index_url("community"),
            format!("https://dl-cdn.alpinelinux.org/alpine/v3.24/community/{arch}/APKINDEX.tar.gz")
        );
    }

    #[test]
    fn apkindex_entry_matches_plain_and_nested_paths() {
        assert!(is_apkindex_entry(std::path::Path::new("APKINDEX")));
        assert!(is_apkindex_entry(std::path::Path::new("./APKINDEX")));
        assert!(is_apkindex_entry(std::path::Path::new("repo/APKINDEX")));
        assert!(!is_apkindex_entry(std::path::Path::new("DESCRIPTION")));
    }

    #[test]
    fn test_parse_apkindex_basic() {
        let content = "P:ripgrep\nV:14.1.1-r0\nT:Search tool\nI:12345\nD:so:libc.musl-x86_64.so.1 pcre2\np:rg=14.1.1-r0\n\n";
        let packages = parse_apkindex(
            content,
            "https://dl-cdn.alpinelinux.org/alpine",
            "v3.20",
            "community",
            "x86_64",
        );
        assert_eq!(packages.len(), 1);
        let pkg = &packages[0];
        assert_eq!(pkg.name, "ripgrep");
        assert_eq!(pkg.version, "14.1.1-r0");
        assert_eq!(pkg.provides, vec!["rg"]);
    }

    #[test]
    fn parse_apkindex_archive_reads_apkindex_member() {
        let mut tarball = Vec::new();
        {
            let encoder = flate2::write::GzEncoder::new(&mut tarball, flate2::Compression::fast());
            let mut archive = tar::Builder::new(encoder);
            let signature = b"signature";
            let mut sig_header = tar::Header::new_gnu();
            sig_header
                .set_path(".SIGN.RSA.alpine-devel@example.rsa.pub")
                .expect("failed to set path for signature header");
            sig_header.set_size(signature.len() as u64);
            sig_header.set_cksum();
            archive.append(&sig_header, &signature[..]).expect("failed to append signature to archive");

            let content = b"P:ripgrep\nV:15.1.0-r0\nT:Search tool\nI:12345\nD:so:libc.musl-aarch64.so.1\np:cmd:rg=15.1.0-r0\n\n";
            let mut header = tar::Header::new_gnu();
            header.set_path("APKINDEX").expect("failed to set path for APKINDEX header");
            header.set_size(content.len() as u64);
            header.set_cksum();
            archive.append(&header, &content[..]).expect("failed to append APKINDEX to archive");
            archive.finish().expect("failed to finish archive");
        }

        let packages = parse_apkindex_archive(
            &tarball,
            "https://dl-cdn.alpinelinux.org/alpine",
            "v3.24",
            "community",
            "aarch64",
        )
        .expect("failed to parse APKINDEX archive");
        assert_eq!(packages.len(), 1);
        assert_eq!(packages[0].name, "ripgrep");
    }
}

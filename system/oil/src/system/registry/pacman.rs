use super::{PackageIndex, PackageMetadata};
use crate::error::{Result, OilError};
use flate2::read::GzDecoder;
use std::collections::HashMap;
use std::io::Read;
use std::time::{Duration, SystemTime};
use tar::Archive;
use tracing::{debug, warn};

pub struct PacmanRegistry {
    mirror: String,
    repos: Vec<String>,
    arch: String,
}

impl PacmanRegistry {
    pub fn new(mirror: &str) -> Self {
        let arch = std::env::consts::ARCH;
        Self {
            mirror: mirror.to_string(),
            repos: vec!["core".to_string(), "extra".to_string()],
            arch: arch.to_string(),
        }
    }

    pub fn arch_default() -> Self {
        Self::new("https://geo.mirror.pkgbuild.com")
    }

    fn cache_path(&self, repo: &str) -> Result<std::path::PathBuf> {
        let dir = crate::ui::dirs::oil_cache_dir()?.join("system");
        std::fs::create_dir_all(&dir)?;
        Ok(dir.join(format!(
            "pacman-{}-{}-{}.json",
            cache_key(&self.mirror),
            cache_key(repo),
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
        let mut all_packages: Vec<PackageMetadata> = Vec::new();

        for repo in &self.repos {
            let cache_path = self.cache_path(repo)?;

            if Self::is_cache_fresh(&cache_path) {
                debug!("Loading pacman index from cache: {:?}", cache_path);
                let data = std::fs::read_to_string(&cache_path)?;
                let packages: Vec<PackageMetadata> = serde_json::from_str(&data)?;
                all_packages.extend(packages);
                continue;
            }

            let url = format!("{}/{}/os/{}/{}.db", self.mirror, repo, self.arch, repo);
            debug!("Fetching pacman db: {}", url);

            let resp = client.get(&url).send().await.map_err(|e| {
                OilError::InstallError(format!("Failed to fetch pacman db from {}: {}", url, e))
            })?;

            if !resp.status().is_success() {
                warn!(
                    "Pacman db fetch failed for repo {}: HTTP {}",
                    repo,
                    resp.status()
                );
                continue;
            }

            let bytes = resp.bytes().await.map_err(|e| {
                OilError::InstallError(format!("Failed to read pacman db body: {}", e))
            })?;

            let pkgs = parse_pacman_db(&bytes, &self.mirror, repo, &self.arch).map_err(|e| {
                OilError::InstallError(format!("Failed to parse pacman db for {}: {}", repo, e))
            })?;

            debug!("Parsed {} packages from {}", pkgs.len(), repo);

            let json = serde_json::to_string(&pkgs)?;
            std::fs::write(&cache_path, &json)?;

            all_packages.extend(pkgs);
        }

        // Deduplicate by name, keeping first seen
        let mut seen = std::collections::HashSet::new();
        all_packages.retain(|p| seen.insert(p.name.clone()));

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

fn parse_pacman_db(
    bytes: &[u8],
    mirror: &str,
    repo: &str,
    arch: &str,
) -> Result<Vec<PackageMetadata>> {
    let decoder = GzDecoder::new(bytes);
    let mut archive = Archive::new(decoder);
    let mut packages: HashMap<String, PackageMetadata> = HashMap::new();

    for entry in archive
        .entries()
        .map_err(|e| OilError::InstallError(format!("Failed to read pacman tar: {}", e)))?
    {
        let mut entry = entry
            .map_err(|e| OilError::InstallError(format!("Failed to read tar entry: {}", e)))?;

        let entry_path = entry
            .path()
            .map_err(|e| OilError::InstallError(format!("Bad path: {}", e)))?
            .to_string_lossy()
            .to_string();

        // We only care about desc files
        if !entry_path.ends_with("/desc") {
            continue;
        }

        let mut content = String::new();
        entry
            .read_to_string(&mut content)
            .map_err(|e| OilError::InstallError(format!("Failed to read desc: {}", e)))?;

        if let Some(pkg) = parse_desc(&content, mirror, repo, arch) {
            packages.insert(pkg.name.clone(), pkg);
        }
    }

    Ok(packages.into_values().collect())
}

fn parse_desc(content: &str, mirror: &str, repo: &str, arch: &str) -> Option<PackageMetadata> {
    let fields = parse_desc_fields(content);

    let name = fields.get("NAME")?.first()?.clone();
    let version = fields.get("VERSION")?.first()?.clone();
    let description = fields
        .get("DESC")
        .and_then(|v| v.first())
        .cloned()
        .unwrap_or_default();
    let filename = fields
        .get("FILENAME")
        .and_then(|v| v.first())
        .cloned()
        .unwrap_or_default();
    let sha256 = fields.get("SHA256SUM").and_then(|v| v.first()).cloned();
    let installed_size: u64 = fields
        .get("ISIZE")
        .and_then(|v| v.first())
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    let depends = fields
        .get("DEPENDS")
        .cloned()
        .unwrap_or_default()
        .iter()
        .map(|d| super::parse_dep_name(d).to_string())
        .filter(|d| !d.is_empty())
        .collect();
    let provides = fields
        .get("PROVIDES")
        .cloned()
        .unwrap_or_default()
        .iter()
        .map(|p| super::parse_dep_name(p).to_string())
        .filter(|p| !p.is_empty())
        .collect();

    let download_url = if filename.is_empty() {
        format!(
            "{}/{}/os/{}/{}-{}-{}.pkg.tar.zst",
            mirror, repo, arch, name, version, arch
        )
    } else {
        format!("{}/{}/os/{}/{}", mirror, repo, arch, filename)
    };

    Some(PackageMetadata {
        name,
        version,
        description,
        download_url,
        sha256,
        installed_size,
        depends,
        provides,
    })
}

fn parse_desc_fields(content: &str) -> HashMap<String, Vec<String>> {
    let mut fields: HashMap<String, Vec<String>> = HashMap::new();
    let mut current_key = String::new();
    let mut current_values: Vec<String> = Vec::new();

    for line in content.lines() {
        let line = line.trim();
        if line.starts_with('%') && line.ends_with('%') {
            if !current_key.is_empty() {
                fields.insert(current_key.clone(), current_values.clone());
            }
            current_key = line.trim_matches('%').to_string();
            current_values = Vec::new();
        } else if line.is_empty() {
            if !current_key.is_empty() {
                fields.insert(current_key.clone(), current_values.clone());
                current_key = String::new();
                current_values = Vec::new();
            }
        } else if !current_key.is_empty() {
            current_values.push(line.to_string());
        }
    }

    if !current_key.is_empty() {
        fields.insert(current_key, current_values);
    }

    fields
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_desc_basic() {
        let desc = r#"%NAME%
ripgrep

%VERSION%
14.1.1-1

%DESC%
A search tool that combines grep and the silver searcher

%FILENAME%
ripgrep-14.1.1-1-x86_64.pkg.tar.zst

%SHA256SUM%
abc123

%ISIZE%
12345

%DEPENDS%
gcc-libs
pcre2>=10.43

%PROVIDES%
rg=14.1.1

"#;
        let pkg = parse_desc(desc, "https://geo.mirror.pkgbuild.com", "extra", "x86_64").unwrap();

        assert_eq!(pkg.name, "ripgrep");
        assert_eq!(pkg.version, "14.1.1-1");
        assert_eq!(pkg.sha256.as_deref(), Some("abc123"));
        assert_eq!(pkg.depends, vec!["gcc-libs", "pcre2"]);
        assert_eq!(pkg.provides, vec!["rg"]);
        assert_eq!(
            pkg.download_url,
            "https://geo.mirror.pkgbuild.com/extra/os/x86_64/ripgrep-14.1.1-1-x86_64.pkg.tar.zst"
        );
    }
}

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::Read;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use crate::error::{OilError, Result};
use crate::system::registry::{PackageIndex, PackageMetadata};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tap {
    pub name: String,
    pub url: String,
}

fn taps_path() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|d| d.join(".oil").join("taps.json"))
        .ok_or_else(|| OilError::Install("$HOME not set".into()))
}

pub struct Taps {
    taps: HashMap<String, Tap>,
}

impl Taps {
    pub fn new() -> Result<Self> {
        let path = taps_path()?;
        let taps = if path.exists() {
            let raw = std::fs::read_to_string(&path)?;
            serde_json::from_str(&raw).unwrap_or_default()
        } else {
            HashMap::new()
        };
        Ok(Self { taps })
    }

    pub fn save(&self) -> Result<()> {
        let path = taps_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(&self.taps)?)?;
        Ok(())
    }

    pub fn add(&mut self, name: &str, url: &str) {
        self.taps.insert(
            name.to_string(),
            Tap {
                name: name.to_string(),
                url: url.to_string(),
            },
        );
    }

    pub fn remove(&mut self, name: &str) {
        self.taps.remove(name);
    }

    pub fn list(&self) -> Vec<&Tap> {
        let mut taps: Vec<_> = self.taps.values().collect();
        taps.sort_by(|a, b| a.name.cmp(&b.name));
        taps
    }
}

pub fn normalize_tap(name: &str) -> (String, String) {
    if name.starts_with("http://") || name.starts_with("https://") || name.starts_with("git@") {
        (name.to_string(), name.to_string())
    } else if name.matches('/').count() == 1 && !name.starts_with('/') && !name.ends_with('/') {
        let trimmed = name.trim_end_matches(".git");
        (name.to_string(), format!("https://github.com/{}", trimmed))
    } else {
        (name.to_string(), name.to_string())
    }
}

pub struct TapRegistry {
    name: String,
    url: String,
}

impl TapRegistry {
    pub fn new(name: &str, url: &str) -> Self {
        Self {
            name: name.to_string(),
            url: url.to_string(),
        }
    }

    fn index_url(&self) -> String {
        if self.url.starts_with("https://github.com/") {
            let path = self.url.trim_start_matches("https://github.com/");
            format!("https://raw.githubusercontent.com/{}/main/index.json", path)
        } else {
            format!("{}/index.json", self.url.trim_end_matches('/'))
        }
    }

    fn cache_path(&self) -> Result<PathBuf> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| OilError::Install("$HOME not set".into()))?;
        let dir = home.join(".oil").join("cache").join("taps");
        std::fs::create_dir_all(&dir)?;
        Ok(dir.join(format!("tap-{}.json", cache_key(&self.name))))
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

    pub fn update(&self) -> Result<PackageIndex> {
        let cache_path = self.cache_path()?;
        let url = self.index_url();
        eprintln!("Fetching tap index: {url}");
        let resp = ureq::get(&url)
            .call()
            .map_err(|e| OilError::Install(format!("Failed to fetch tap index from {url}: {e}")))?;
        let mut body = Vec::new();
        resp.into_body()
            .into_reader()
            .read_to_end(&mut body)
            .map_err(|e| OilError::Install(format!("Failed to read tap index body: {e}")))?;
        let packages: Vec<PackageMetadata> = serde_json::from_slice(&body)
            .map_err(|e| OilError::Install(format!("Failed to parse tap index: {e}")))?;
        if let Some(parent) = cache_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&cache_path, &body)?;
        Ok(PackageIndex::new(packages))
    }

    pub fn load(&self) -> Result<PackageIndex> {
        let cache_path = self.cache_path()?;
        if Self::is_cache_fresh(&cache_path) {
            let data = std::fs::read_to_string(&cache_path)?;
            let packages: Vec<PackageMetadata> = serde_json::from_str(&data)?;
            return Ok(PackageIndex::new(packages));
        }
        self.update()
    }
}

fn cache_key(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_user_repo_shorthand() {
        let (name, url) = normalize_tap("undivisible/tap");
        assert_eq!(name, "undivisible/tap");
        assert_eq!(url, "https://github.com/undivisible/tap");
    }

    #[test]
    fn normalize_url_passthrough() {
        let (name, url) = normalize_tap("https://example.com/tap");
        assert_eq!(name, "https://example.com/tap");
        assert_eq!(url, "https://example.com/tap");
    }

    #[test]
    fn normalize_git_url_passthrough() {
        let (name, url) = normalize_tap("git@github.com:undivisible/tap.git");
        assert_eq!(name, "git@github.com:undivisible/tap.git");
        assert_eq!(url, "git@github.com:undivisible/tap.git");
    }

    #[test]
    fn index_url_for_github_repo() {
        let registry = TapRegistry::new("undivisible/tap", "https://github.com/undivisible/tap");
        assert_eq!(
            registry.index_url(),
            "https://raw.githubusercontent.com/undivisible/tap/main/index.json"
        );
    }

    #[test]
    fn index_url_for_plain_url() {
        let registry = TapRegistry::new("mytap", "https://example.com/tap");
        assert_eq!(registry.index_url(), "https://example.com/tap/index.json");
    }
}

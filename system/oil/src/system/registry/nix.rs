/// Nix packages registry — direct binary cache integration.
///
/// Oil handles Nix packages without the `nix` CLI:
/// 1. Fetches nixpkgs package index from channels endpoint
/// 2. Resolves store paths to binary cache URLs
/// 3. Downloads + extracts NAR archives directly
use super::{PackageIndex, PackageMetadata};
use crate::error::{Result, OilError};
use std::time::{Duration, SystemTime};
use tracing::debug;

pub struct NixRegistry {
    channel_url: String,
    cache_url: String,
    system: String,
}

impl NixRegistry {
    pub fn new(channel_url: &str, cache_url: &str, system: &str) -> Self {
        Self { channel_url: channel_url.trim_end_matches('/').to_string(), cache_url: cache_url.trim_end_matches('/').to_string(), system: system.to_string() }
    }

    pub fn default() -> Self {
        let arch = std::env::consts::ARCH;
        let system: String = match arch {
            "x86_64" => "x86_64-linux".to_string(),
            "aarch64" => "aarch64-linux".to_string(),
            other => format!("{}-linux", other),
        };
        Self::new("https://channels.nixos.org/nixos-unstable", "https://cache.nixos.org", &system)
    }

    fn cache_path() -> Result<std::path::PathBuf> {
        let dir = crate::ui::dirs::oil_cache_dir()?.join("system");
        std::fs::create_dir_all(&dir)?;
        Ok(dir.join("nix-index.json"))
    }

    fn is_cache_fresh(path: &std::path::Path) -> bool {
        if let Ok(meta) = std::fs::metadata(path) {
            if let Ok(modified) = meta.modified() {
                if let Ok(elapsed) = SystemTime::now().duration_since(modified) {
                    return elapsed < Duration::from_secs(3600);
                }
            }
        }
        false
    }

    pub async fn load(&self, client: &reqwest::Client) -> Result<PackageIndex> {
        let cache_path = Self::cache_path()?;
        if Self::is_cache_fresh(&cache_path) {
            debug!("Loading Nix index from cache");
            let data = std::fs::read_to_string(&cache_path)?;
            let packages: Vec<PackageMetadata> = serde_json::from_str(&data)?;
            return Ok(PackageIndex { packages });
        }

        // Fetch nixpkgs package index from channels endpoint
        let index_url = format!("{}/packages.json", self.channel_url);
        debug!("Fetching nixpkgs index from {}", index_url);
        let resp = client.get(&index_url).send().await.map_err(|e| {
            OilError::InstallError(format!("Failed to fetch nixpkgs index: {}", e))
        })?;
        if !resp.status().is_success() {
            return Err(OilError::InstallError(format!("nixpkgs index HTTP {}", resp.status())));
        }
        let bytes = resp.bytes().await.map_err(|e| {
            OilError::InstallError(format!("Failed to read nixpkgs index: {}", e))
        })?;

        // Parse the packages.json array
        let entries: Vec<NixpkgsEntry> = serde_json::from_slice(&bytes).map_err(|e| {
            OilError::InstallError(format!("Failed to parse nixpkgs index JSON: {}", e))
        })?;

        let mut packages = Vec::new();
        for entry in entries {
            // Skip entries not matching our system
            if entry.system != self.system {
                continue;
            }

            let name = entry.pname.clone().unwrap_or_else(|| {
                entry.name.split('-').next().unwrap_or(&entry.name).to_string()
            });
            let store_hash = entry.store_path.trim_start_matches("/nix/store/").split('-').next().unwrap_or("").to_string();

            // Binary cache narinfo URL — resolves to a .nar.zst download
            let download_url = if !store_hash.is_empty() {
                format!("{}/{}.narinfo", self.cache_url, store_hash)
            } else {
                String::new()
            };

            packages.push(PackageMetadata {
                name,
                version: entry.version.unwrap_or_default(),
                description: entry.description.unwrap_or_default(),
                download_url,
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec![entry.attr_path],
            });
        }

        let json = serde_json::to_string(&packages)?;
        let _ = std::fs::write(&cache_path, &json);
        debug!("Loaded {} packages from nixpkgs index", packages.len());

        Ok(PackageIndex { packages })
    }
}

/// Schema for nixpkgs packages.json entries
#[derive(Debug, serde::Deserialize)]
struct NixpkgsEntry {
    attr_path: String,
    name: String,
    pname: Option<String>,
    version: Option<String>,
    system: String,
    store_path: String,
    description: Option<String>,
}

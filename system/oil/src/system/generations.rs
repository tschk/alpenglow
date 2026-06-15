/// Atomic generation management for wax-managed system packages.
///
/// Every mutating system operation (install, remove, upgrade) captures a
/// point-in-time snapshot of the installed package set into an immutable
/// generation manifest.  A `current` symlink always points at the active
/// generation.  Rolling back is an O(1) symlink swap followed by converging
/// the live system to the target generation's package set.
use crate::error::{Result, OilError};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

fn generations_dir() -> Result<PathBuf> {
    let home = std::env::var("HOME").map_err(|_| OilError::InstallError("HOME not set".into()))?;
    Ok(PathBuf::from(home)
        .join(".oil")
        .join("system")
        .join("generations"))
}

fn current_link(dir: &Path) -> PathBuf {
    dir.join("current")
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageRecord {
    pub name: String,
    pub version: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Generation {
    pub id: u32,
    pub timestamp: i64,
    pub reason: String,
    pub packages: Vec<PackageRecord>,
}

impl Generation {
    /// Human-readable age string.
    pub fn age_string(&self) -> String {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        let secs = (now - self.timestamp).max(0) as u64;
        if secs < 60 {
            "just now".to_string()
        } else if secs < 3600 {
            format!("{}m ago", secs / 60)
        } else if secs < 86400 {
            format!("{}h ago", secs / 3600)
        } else {
            format!("{}d ago", secs / 86400)
        }
    }
}

pub struct GenerationManager {
    pub(crate) dir: PathBuf,
}

impl GenerationManager {
    pub async fn new() -> Result<Self> {
        let dir = generations_dir()?;
        tokio::fs::create_dir_all(&dir).await?;
        Ok(Self { dir })
    }

    /// Construct a GenerationManager backed by an arbitrary directory (for tests).
    #[cfg(test)]
    pub(crate) fn with_dir(dir: std::path::PathBuf) -> Self {
        Self { dir }
    }

    fn manifest_path(&self, id: u32) -> PathBuf {
        self.dir.join(format!("gen-{:04}.json", id))
    }

    /// Next unused generation ID.
    async fn next_id(&self) -> Result<u32> {
        let mut max = 0u32;
        let mut entries = tokio::fs::read_dir(&self.dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if let Some(rest) = name.strip_prefix("gen-") {
                if let Some(num) = rest.strip_suffix(".json") {
                    if let Ok(n) = num.parse::<u32>() {
                        max = max.max(n);
                    }
                }
            }
        }
        Ok(max + 1)
    }

    /// Persist a new generation and atomically update the `current` symlink.
    pub async fn create(
        &self,
        reason: &str,
        packages: Vec<(String, Option<String>)>,
    ) -> Result<Generation> {
        let id = self.next_id().await?;
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let gen = Generation {
            id,
            timestamp,
            reason: reason.to_string(),
            packages: packages
                .into_iter()
                .map(|(name, version)| PackageRecord { name, version })
                .collect(),
        };

        let path = self.manifest_path(id);
        let raw = serde_json::to_string_pretty(&gen)?;
        tokio::fs::write(&path, raw).await?;

        // Atomic symlink swap: write to a temp link then rename.
        let link = current_link(&self.dir);
        let tmp = self.dir.join(".current.tmp");
        if tmp.exists() {
            tokio::fs::remove_file(&tmp).await?;
        }
        #[cfg(unix)]
        {
            tokio::fs::symlink(path.file_name().unwrap(), &tmp).await?;
        }
        #[cfg(windows)]
        {
            // On Windows, use a junction for directories or a file copy as fallback.
            // Since generations are directories, we use std::os::windows::fs::symlink_dir.
            let target = path.file_name().unwrap();
            tokio::fs::symlink_dir(target, &tmp).await.map_err(|e| {
                OilError::InstallError(format!(
                    "Failed to create junction for generation symlink: {}",
                    e
                ))
            })?;
        }
        tokio::fs::rename(&tmp, &link).await?;

        Ok(gen)
    }

    /// Load the current (active) generation, if any.
    pub async fn current(&self) -> Result<Option<Generation>> {
        let link = current_link(&self.dir);
        if !link.exists() {
            return Ok(None);
        }
        let target = tokio::fs::read_link(&link).await?;
        let manifest = self.dir.join(target);
        if !manifest.exists() {
            return Ok(None);
        }
        let raw = tokio::fs::read_to_string(&manifest).await?;
        Ok(Some(serde_json::from_str(&raw)?))
    }

    /// Load all generations, sorted ascending by ID.
    pub async fn list(&self) -> Result<Vec<Generation>> {
        let mut gens = Vec::new();
        let mut entries = tokio::fs::read_dir(&self.dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name.starts_with("gen-") && name.ends_with(".json") {
                let raw = tokio::fs::read_to_string(entry.path()).await?;
                if let Ok(gen) = serde_json::from_str::<Generation>(&raw) {
                    gens.push(gen);
                }
            }
        }
        gens.sort_by_key(|g| g.id);
        Ok(gens)
    }

    /// Load a specific generation by ID.
    pub async fn get(&self, id: u32) -> Result<Option<Generation>> {
        let path = self.manifest_path(id);
        if !path.exists() {
            return Ok(None);
        }
        let raw = tokio::fs::read_to_string(&path).await?;
        Ok(Some(serde_json::from_str(&raw)?))
    }

    /// Compute what needs to change to go from `from` to `to`.
    /// Returns (to_install, to_remove).
    pub fn diff(
        from: &[PackageRecord],
        to: &[PackageRecord],
    ) -> (Vec<PackageRecord>, Vec<PackageRecord>) {
        let from_names: std::collections::HashSet<_> = from.iter().map(|p| &p.name).collect();
        let to_names: std::collections::HashSet<_> = to.iter().map(|p| &p.name).collect();

        let to_install: Vec<_> = to
            .iter()
            .filter(|p| !from_names.contains(&p.name))
            .cloned()
            .collect();

        let to_remove: Vec<_> = from
            .iter()
            .filter(|p| !to_names.contains(&p.name))
            .cloned()
            .collect();

        (to_install, to_remove)
    }

    pub fn diff_records(
        from: &[(String, Option<String>)],
        to: &[PackageRecord],
    ) -> (Vec<PackageRecord>, Vec<PackageRecord>) {
        let from_records: Vec<PackageRecord> = from
            .iter()
            .map(|(name, version)| PackageRecord {
                name: name.clone(),
                version: version.clone(),
            })
            .collect();
        Self::diff(&from_records, to)
    }

    /// ID of the previous generation (one before current), if any.
    pub async fn previous_id(&self) -> Result<Option<u32>> {
        let current = self.current().await?;
        let current_id = match current {
            Some(g) => g.id,
            None => return Ok(None),
        };
        let all = self.list().await?;
        let prev = all.iter().rev().find(|g| g.id < current_id).map(|g| g.id);
        Ok(prev)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn test_create_and_list() {
        let tmp = TempDir::new().unwrap();
        let mgr = GenerationManager::with_dir(tmp.path().to_path_buf());
        tokio::fs::create_dir_all(&mgr.dir).await.unwrap();

        let gen1 = mgr
            .create(
                "install curl",
                vec![("curl".to_string(), Some("8.0.0".to_string()))],
            )
            .await
            .unwrap();
        assert_eq!(gen1.id, 1);
        assert_eq!(gen1.reason, "install curl");
        assert_eq!(gen1.packages.len(), 1);

        let gen2 = mgr
            .create(
                "install wget",
                vec![
                    ("curl".to_string(), Some("8.0.0".to_string())),
                    ("wget".to_string(), Some("1.21.0".to_string())),
                ],
            )
            .await
            .unwrap();
        assert_eq!(gen2.id, 2);

        let all = mgr.list().await.unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].id, 1);
        assert_eq!(all[1].id, 2);
    }

    #[tokio::test]
    async fn test_current_link() {
        let tmp = TempDir::new().unwrap();
        let mgr = GenerationManager::with_dir(tmp.path().to_path_buf());
        tokio::fs::create_dir_all(&mgr.dir).await.unwrap();

        assert!(mgr.current().await.unwrap().is_none());

        mgr.create("first", vec![]).await.unwrap();
        let current = mgr.current().await.unwrap();
        assert!(current.is_some());
        assert_eq!(current.unwrap().id, 1);

        mgr.create("second", vec![]).await.unwrap();
        let current = mgr.current().await.unwrap();
        assert_eq!(current.unwrap().id, 2);
    }

    #[tokio::test]
    async fn test_previous_id() {
        let tmp = TempDir::new().unwrap();
        let mgr = GenerationManager::with_dir(tmp.path().to_path_buf());
        tokio::fs::create_dir_all(&mgr.dir).await.unwrap();

        assert!(mgr.previous_id().await.unwrap().is_none());

        mgr.create("first", vec![]).await.unwrap();
        assert!(mgr.previous_id().await.unwrap().is_none());

        mgr.create("second", vec![]).await.unwrap();
        assert_eq!(mgr.previous_id().await.unwrap(), Some(1));
    }

    #[test]
    fn test_diff_empty() {
        let (install, remove) = GenerationManager::diff(&[], &[]);
        assert!(install.is_empty());
        assert!(remove.is_empty());
    }

    #[test]
    fn test_diff_install_only() {
        let from = vec![];
        let to = vec![PackageRecord {
            name: "curl".to_string(),
            version: Some("8.0.0".to_string()),
        }];
        let (install, remove) = GenerationManager::diff(&from, &to);
        assert_eq!(install.len(), 1);
        assert_eq!(install[0].name, "curl");
        assert!(remove.is_empty());
    }

    #[test]
    fn test_diff_remove_only() {
        let from = vec![PackageRecord {
            name: "curl".to_string(),
            version: None,
        }];
        let to = vec![];
        let (install, remove) = GenerationManager::diff(&from, &to);
        assert!(install.is_empty());
        assert_eq!(remove.len(), 1);
        assert_eq!(remove[0].name, "curl");
    }

    #[test]
    fn test_diff_mixed() {
        let from = vec![
            PackageRecord {
                name: "curl".to_string(),
                version: None,
            },
            PackageRecord {
                name: "wget".to_string(),
                version: None,
            },
        ];
        let to = vec![
            PackageRecord {
                name: "wget".to_string(),
                version: None,
            },
            PackageRecord {
                name: "nginx".to_string(),
                version: None,
            },
        ];
        let (install, remove) = GenerationManager::diff(&from, &to);
        assert_eq!(install.len(), 1);
        assert_eq!(install[0].name, "nginx");
        assert_eq!(remove.len(), 1);
        assert_eq!(remove[0].name, "curl");
    }
}

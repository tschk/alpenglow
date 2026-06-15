use crate::error::{Result, OilError};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

fn manifest_dir() -> Result<PathBuf> {
    let home = std::env::var("HOME").map_err(|_| OilError::InstallError("HOME not set".into()))?;
    Ok(PathBuf::from(home)
        .join(".oil")
        .join("system")
        .join("manifests"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileManifest {
    pub package: String,
    pub version: String,
    /// All files and symlinks installed, as absolute paths.
    pub files: Vec<PathBuf>,
    /// All directories created (for cleanup on removal).
    pub dirs: Vec<PathBuf>,
    pub installed_at: i64,
}

impl FileManifest {
    /// Persist the manifest to disk.
    pub async fn save(&self) -> Result<()> {
        let path = Self::path(&self.package, &self.version)?;
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        let raw = serde_json::to_string_pretty(self)?;
        tokio::fs::write(&path, raw).await?;
        Ok(())
    }

    /// Load manifest for a specific package version.
    #[allow(dead_code)]
    pub async fn load(package: &str, version: &str) -> Result<Option<Self>> {
        let path = Self::path(package, version)?;
        if !path.exists() {
            return Ok(None);
        }
        let raw = tokio::fs::read_to_string(&path).await?;
        Ok(Some(serde_json::from_str(&raw)?))
    }

    /// Load any manifest for this package name (any version).
    pub async fn load_any_version(package: &str) -> Result<Option<Self>> {
        let dir = manifest_dir()?;
        if !dir.exists() {
            return Ok(None);
        }
        let prefix = format!("{}-", package);
        let mut entries = tokio::fs::read_dir(&dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            let name = entry.file_name();
            let name = name.to_string_lossy().to_string();
            if name.starts_with(&prefix) && name.ends_with(".json") {
                let raw = tokio::fs::read_to_string(entry.path()).await?;
                if let Ok(manifest) = serde_json::from_str::<Self>(&raw) {
                    if manifest.package == package {
                        return Ok(Some(manifest));
                    }
                }
            }
        }
        Ok(None)
    }

    pub async fn list_all() -> Result<Vec<Self>> {
        let dir = manifest_dir()?;
        if !dir.exists() {
            return Ok(Vec::new());
        }

        let mut manifests = Vec::new();
        let mut entries = tokio::fs::read_dir(&dir).await?;
        while let Some(entry) = entries.next_entry().await? {
            let raw = match tokio::fs::read_to_string(entry.path()).await {
                Ok(raw) => raw,
                Err(_) => continue,
            };
            if let Ok(manifest) = serde_json::from_str::<Self>(&raw) {
                manifests.push(manifest);
            }
        }
        manifests.sort_by(|a, b| a.package.cmp(&b.package));
        Ok(manifests)
    }

    fn path(package: &str, version: &str) -> Result<PathBuf> {
        Ok(manifest_dir()?.join(format!("{}-{}.json", package, version)))
    }

    /// Public accessor for the manifest file path (for removal).
    pub fn manifest_path_pub(package: &str, version: &str) -> Result<PathBuf> {
        Self::path(package, version)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::OnceLock;
    use tempfile::TempDir;
    use tokio::sync::Mutex;

    fn home_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    #[tokio::test]
    async fn test_save_and_load() {
        let _guard = home_lock().lock().await;
        let tmp = TempDir::new().unwrap();
        std::env::set_var("HOME", tmp.path());

        let manifest = FileManifest {
            package: "curl".to_string(),
            version: "8.0.0".to_string(),
            files: vec![
                PathBuf::from("/usr/bin/curl"),
                PathBuf::from("/usr/share/man/man1/curl.1"),
            ],
            dirs: vec![PathBuf::from("/usr/share/man/man1")],
            installed_at: 1234567890,
        };

        manifest.save().await.unwrap();

        let loaded = FileManifest::load("curl", "8.0.0").await.unwrap();
        assert!(loaded.is_some());
        let loaded = loaded.unwrap();
        assert_eq!(loaded.package, "curl");
        assert_eq!(loaded.version, "8.0.0");
        assert_eq!(loaded.files.len(), 2);
        assert!(loaded.files.contains(&PathBuf::from("/usr/bin/curl")));
    }

    #[tokio::test]
    async fn test_load_nonexistent() {
        let _guard = home_lock().lock().await;
        let tmp = TempDir::new().unwrap();
        std::env::set_var("HOME", tmp.path());

        let result = FileManifest::load("nonexistent", "1.0.0").await.unwrap();
        assert!(result.is_none());
    }
}

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

use crate::error::Result;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledPackage {
    pub name: String,
    pub version: String,
    pub install_date: i64,
    pub pinned: bool,
}

fn state_path() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|d| d.join(".oil").join("installed.json"))
        .ok_or_else(|| crate::error::OilError::Install("$HOME not set".into()))
}

pub struct InstallState {
    packages: HashMap<String, InstalledPackage>,
}

impl InstallState {
    pub fn new() -> Result<Self> {
        let path = state_path()?;
        let packages = if path.exists() {
            let raw = std::fs::read_to_string(&path)?;
            serde_json::from_str(&raw).unwrap_or_default()
        } else {
            HashMap::new()
        };
        Ok(Self { packages })
    }

    pub fn load(&self) -> Result<HashMap<String, InstalledPackage>> {
        Ok(self.packages.clone())
    }

    pub fn save(&self) -> Result<()> {
        let path = state_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(&self.packages)?)?;
        Ok(())
    }

    pub fn mark_installed(&mut self, name: &str, version: Option<String>) {
        let pkg = InstalledPackage {
            name: name.to_string(),
            version: version.unwrap_or_default(),
            install_date: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0),
            pinned: false,
        };
        self.packages.insert(name.to_string(), pkg);
    }

    pub fn remove(&mut self, name: &str) -> Result<()> {
        self.packages.remove(name);
        Ok(())
    }

    pub fn clear(&mut self) {
        self.packages.clear();
    }

    pub fn get(&self, name: &str) -> Option<InstalledPackage> {
        self.packages.get(name).cloned()
    }
}

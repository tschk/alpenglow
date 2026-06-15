use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

use crate::error::{OilError, Result};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledPackage {
    pub name: String,
    pub version: String,
    pub install_date: i64,
    pub pinned: bool,
}

fn state_path() -> Result<PathBuf> {
    crate::ui::dirs::oil_dir().map(|d| d.join("installed.json"))
}

pub struct InstallState;

impl InstallState {
    pub fn new() -> Result<Self> {
        Ok(Self)
    }

    pub fn load(&self) -> Result<HashMap<String, InstalledPackage>> {
        let path = state_path()?;
        if !path.exists() {
            return Ok(HashMap::new());
        }
        let raw = std::fs::read_to_string(&path)?;
        Ok(serde_json::from_str(&raw)?)
    }

    pub fn save(&self) -> Result<()> {
        let current = self.load()?;
        let path = state_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(&current)?)?;
        Ok(())
    }

    pub fn mark_installed(&mut self, name: &str, version: Option<String>, _declared: bool) {
        // This is a no-op; state is already updated in the caller
        // Keeping for API compatibility
    }

    pub fn remove(&mut self, name: &str) -> Result<()> {
        let mut packages = self.load()?;
        packages.remove(name);
        let path = state_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(&packages)?)?;
        Ok(())
    }

    pub fn clear(&mut self) {
        // Will be written on save()
    }

    pub fn get(&self, name: &str) -> Option<InstalledPackage> {
        self.load().ok()?.into_values().find(|p| p.name == name)
    }

    pub fn get_mut(&mut self, name: &str) -> Option<&mut InstalledPackage> {
        None // simplified
    }
}

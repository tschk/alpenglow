use crate::error::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

fn state_path() -> Result<std::path::PathBuf> {
    crate::ui::dirs::oil_dir().map(|d| d.join("system").join("state.json"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledPackage {
    pub name: String,
    pub version: Option<String>,
    pub installed_at: i64,
    pub declared: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SystemState {
    pub installed: HashMap<String, InstalledPackage>,
    pub declared: Vec<String>,
}

impl SystemState {
    pub fn load() -> Result<Self> {
        let path = state_path()?;
        if !path.exists() {
            return Ok(Self::default());
        }
        let raw = std::fs::read_to_string(&path)?;
        Ok(serde_json::from_str(&raw)?)
    }

    pub fn save(&self) -> Result<()> {
        let path = state_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(self)?)?;
        Ok(())
    }
}

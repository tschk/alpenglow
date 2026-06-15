use crate::error::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

fn gens_dir() -> Result<PathBuf> {
    crate::ui::dirs::oil_dir().map(|d| d.join("system").join("generations"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Generation {
    pub id: u32,
    pub packages: Vec<String>,
    pub reason: String,
    pub created_at: i64,
}

pub struct GenerationManager;

impl GenerationManager {
    pub fn new() -> Result<Self> {
        Ok(Self)
    }

    pub fn ensure_initialized(&self) -> Result<()> {
        let dir = gens_dir()?;
        std::fs::create_dir_all(&dir)?;
        Ok(())
    }

    pub fn current(&self) -> Result<Option<Generation>> {
        let dir = gens_dir()?;
        Ok(None)
    }

    pub fn list(&self) -> Result<Vec<Generation>> {
        Ok(Vec::new())
    }
}

use crate::error::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct FileManifest {
    pub files: HashMap<String, String>,
}

impl FileManifest {
    pub fn load(_path: &PathBuf) -> Result<Self> {
        Ok(Self::default())
    }

    pub fn save(&self) -> Result<()> {
        Ok(())
    }
}

pub mod dirs {
    use crate::error::{OilError, Result};
    use std::path::PathBuf;

    pub fn home_dir() -> Result<PathBuf> {
        std::env::var_os("HOME").map(PathBuf::from).ok_or_else(|| {
            OilError::Install("$HOME not set".into())
        })
    }

    pub fn oil_dir() -> Result<PathBuf> {
        Ok(home_dir()?.join(".oil"))
    }

    pub fn oil_cache_dir() -> Result<PathBuf> {
        Ok(oil_dir()?.join("cache"))
    }
}

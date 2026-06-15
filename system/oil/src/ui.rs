use crate::error::Result;
use std::path::Path;

pub fn copy_dir_all(src: &Path, dst: &Path) -> Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());

        if ty.is_dir() {
            copy_dir_all(&src_path, &dst_path)?;
        } else {
            let _ = std::fs::copy(&src_path, &dst_path);
        }
    }
    Ok(())
}

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

pub mod apk;

use crate::error::{OilError, Result};
use std::path::{Path, PathBuf};

pub fn extract_package_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let name = path.to_string_lossy();
    if name.ends_with(".apk") {
        return apk::extract_tracked(path, dest_dir);
    }
    Err(OilError::Install(format!("unknown package format: {name}")))
}

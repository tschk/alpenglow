#[cfg(any(feature = "system-apk", feature = "system-all"))]
pub mod apk;
#[cfg(any(feature = "system-apt", feature = "system-all"))]
pub mod deb;
#[cfg(any(feature = "system-pacman", feature = "system-all"))]
pub mod pacman;
#[cfg(any(feature = "system-dnf", feature = "system-all"))]
pub mod rpm;
#[cfg(any(feature = "system-xbps", feature = "system-all"))]
pub mod xbps;
pub mod nar;

use crate::error::{Result, OilError};
use std::path::{Path, PathBuf};

/// Extract a package and return (files, dirs) — absolute paths of everything extracted.
/// `dest_dir` is the install root.
pub fn extract_package_tracked(
    path: &Path,
    dest_dir: &Path,
) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let name = path.to_string_lossy();
    #[cfg(any(feature = "system-apt", feature = "system-all"))]
    if name.ends_with(".deb") {
        return deb::extract_tracked(path, dest_dir);
    }
    #[cfg(any(feature = "system-pacman", feature = "system-all"))]
    if name.ends_with(".pkg.tar.zst") || name.ends_with(".pkg.tar.xz") || name.ends_with(".pkg.tar.gz") {
        return pacman::extract_tracked(path, dest_dir);
    }
    #[cfg(any(feature = "system-apk", feature = "system-all"))]
    if name.ends_with(".apk") {
        return apk::extract_tracked(path, dest_dir);
    }
    #[cfg(any(feature = "system-dnf", feature = "system-all"))]
    if name.ends_with(".rpm") {
        return rpm::extract_tracked(path, dest_dir);
    }
    #[cfg(any(feature = "system-xbps", feature = "system-all"))]
    if name.ends_with(".xbps") {
        return xbps::extract_tracked(path, dest_dir);
    }
    if name.ends_with(".nar") || name.ends_with(".nar.zst") {
        return nar::extract_nar_tracked(path, dest_dir);
    }
    Err(OilError::InstallError(format!(
        "unknown package format: {}",
        name
    )))
}

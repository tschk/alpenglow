/// Extract a .pkg.tar.zst (or .xz/.gz) pacman package to dest_dir.
/// Skips pacman metadata files: .PKGINFO, .MTREE, .BUILDINFO.
use crate::error::{Result, OilError};
use std::io::Read;
use std::path::{Path, PathBuf};
use tar::Archive;

/// Extract a pacman package and return (files, dirs) of absolute paths written.
pub fn extract_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    std::fs::create_dir_all(dest_dir)?;
    let name = path.to_string_lossy().to_string();
    let file = std::fs::File::open(path)?;

    if name.ends_with(".pkg.tar.zst") {
        let decoder = zstd::Decoder::new(file)
            .map_err(|e| OilError::InstallError(format!("zstd decoder error: {}", e)))?;
        untar(decoder, dest_dir)
    } else if name.ends_with(".pkg.tar.xz") {
        let decoder = xz2::read::XzDecoder::new(file);
        untar(decoder, dest_dir)
    } else if name.ends_with(".pkg.tar.gz") {
        let decoder = flate2::read::GzDecoder::new(file);
        untar(decoder, dest_dir)
    } else {
        Err(OilError::InstallError(format!(
            "Unsupported pacman package format: {}",
            name
        )))
    }
}

const SKIP_FILES: &[&str] = &[".PKGINFO", ".MTREE", ".BUILDINFO", ".INSTALL"];

fn untar<R: Read>(reader: R, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let mut archive = Archive::new(reader);
    let mut files = Vec::new();
    let mut dirs = Vec::new();

    for entry in archive.entries()? {
        let mut entry = entry?;
        let entry_path = entry.path()?;
        let entry_str = entry_path.to_string_lossy().to_string();

        // Skip leading "./"
        let stripped = entry_str.strip_prefix("./").unwrap_or(&entry_str);

        // Skip metadata files
        if SKIP_FILES.contains(&stripped) {
            continue;
        }

        if stripped.is_empty() || stripped.contains("..") {
            continue;
        }

        let dest = dest_dir.join(stripped);

        if entry.header().entry_type().is_dir() {
            std::fs::create_dir_all(&dest)?;
            dirs.push(dest);
        } else if entry.header().entry_type().is_symlink() {
            if let Some(link_target) = entry.link_name()? {
                let _ = std::fs::remove_file(&dest);
                let _ = std::fs::remove_dir_all(&dest);
                if let Some(parent) = dest.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                #[cfg(unix)]
                std::os::unix::fs::symlink(link_target.as_ref(), &dest)?;
                files.push(dest);
            }
        } else {
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent)?;
            }
            entry.unpack(&dest)?;
            files.push(dest);
        }
    }
    Ok((files, dirs))
}

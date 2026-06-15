/// Extract an Alpine .apk package to dest_dir.
///
/// .apk files are concatenated gzip streams:
///   - First stream: signature (skip it)
///   - Second stream: actual tar archive with the package contents
use crate::error::Result;
use flate2::read::MultiGzDecoder;
use std::io::Read;
use std::path::{Path, PathBuf};
use tar::Archive;

/// Extract an APK package and return (files, dirs) of absolute paths written.
pub fn extract_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    std::fs::create_dir_all(dest_dir)?;
    let data = std::fs::read(path)?;
    let decoder = MultiGzDecoder::new(&data[..]);
    untar(decoder, dest_dir)
}

fn untar<R: Read>(reader: R, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let mut archive = Archive::new(reader);
    let mut files = Vec::new();
    let mut dirs = Vec::new();
    let mut entries_buf: Vec<Vec<u8>> = Vec::new();

    // Collect and sort: regular files first, then symlinks & hardlinks
    for entry_result in archive.entries()? {
        let mut entry = entry_result?;
        let entry_path = entry.path()?;
        let entry_str = entry_path.to_string_lossy().to_string();

        if entry_str == ".PKGINFO" || entry_str == ".INSTALL" || entry_str.starts_with(".SIGN.") {
            continue;
        }

        let stripped = entry_str.strip_prefix("./").unwrap_or(&entry_str);
        if stripped.is_empty() || stripped.contains("..") {
            continue;
        }

        let dest = dest_dir.join(stripped);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let kind = entry.header().entry_type();
        if kind.is_dir() {
            std::fs::create_dir_all(&dest)?;
            dirs.push(dest);
        } else if kind.is_symlink() {
            if let Some(link_target) = entry.link_name()? {
                let _ = std::fs::remove_file(&dest);
                let _ = std::fs::remove_dir_all(&dest);
                #[cfg(unix)]
                std::os::unix::fs::symlink(link_target.as_ref(), &dest)?;
                files.push(dest);
            }
        } else if kind.is_hard_link() {
            // ponytail: sort so regular files unpack first, then hard links
            // stash entry bytes and process after regular files
            let mut data = Vec::new();
            entry.read_to_end(&mut data)?;
            entries_buf.push(data);
        } else {
            entry.unpack(&dest)?;
            files.push(dest);
        }
    }

    // Now unpack hard links (regular files should already exist)
    for data in &entries_buf {
        let mut decoder = MultiGzDecoder::new(&data[..]);
        let mut inner = Archive::new(&mut decoder);
        for entry_ in inner.entries()? {
            let mut entry = entry_?;
            let path = entry.path()?.to_string_lossy().to_string();
            let stripped = path.strip_prefix("./").unwrap_or(&path);
            let dest = dest_dir.join(stripped);
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent)?;
            }
            entry.unpack(&dest)?;
            if !entry.header().entry_type().is_dir() {
                files.push(dest);
            }
        }
    }

    Ok((files, dirs))
}

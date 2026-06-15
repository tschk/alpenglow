/// Extract XBPS package (.xbps) — gzip-compressed tar archive.
use crate::error::Result;
use flate2::read::MultiGzDecoder;
use std::io::Read;
use std::path::{Path, PathBuf};
use tar::Archive;

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
    for entry in archive.entries()? {
        let mut entry = entry?;
        let entry_path = entry.path()?;
        let entry_str = entry_path.to_string_lossy().to_string();
        if entry_str.contains(".xbps") || entry_str.starts_with(".XBD") { continue; }
        let stripped = entry_str.strip_prefix("./").unwrap_or(&entry_str);
        if stripped.is_empty() || stripped.contains("..") { continue; }
        let dest = dest_dir.join(stripped);
        if entry.header().entry_type().is_dir() {
            std::fs::create_dir_all(&dest)?; dirs.push(dest);
        } else if entry.header().entry_type().is_symlink() {
            if let Some(target) = entry.link_name()? {
                let _ = std::fs::remove_file(&dest);
                if let Some(parent) = dest.parent() { std::fs::create_dir_all(parent)?; }
                #[cfg(unix)] std::os::unix::fs::symlink(target.as_ref(), &dest)?;
                files.push(dest);
            }
        } else {
            if let Some(parent) = dest.parent() { std::fs::create_dir_all(parent)?; }
            entry.unpack(&dest)?; files.push(dest);
        }
    }
    Ok((files, dirs))
}

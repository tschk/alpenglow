/// Extract a .deb package to dest_dir.
///
/// .deb files are ar(1) archives with the structure:
///   - `debian-binary`   — "2.0\n"
///   - `control.tar.*`   — metadata (skipped)
///   - `data.tar.*`      — the actual file tree (we extract this)
use crate::error::{Result, OilError};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use tar::Archive;

#[allow(dead_code)]
pub fn extract(path: &Path, dest_dir: &Path) -> Result<()> {
    std::fs::create_dir_all(dest_dir)?;
    let file = std::fs::File::open(path)?;
    let mut reader = std::io::BufReader::new(file);

    // Validate the global ar header
    let mut global = [0u8; 8];
    reader.read_exact(&mut global)?;
    if &global != b"!<arch>\n" {
        return Err(OilError::InstallError(
            "Not a valid ar archive (missing global header)".to_string(),
        ));
    }

    loop {
        // Each file header is 60 bytes
        let mut header = [0u8; 60];
        match reader.read_exact(&mut header) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.into()),
        }

        // Filename: bytes 0..16, right-padded with spaces
        let filename_raw = std::str::from_utf8(&header[0..16])
            .map_err(|e| OilError::ParseError(format!("ar filename: {}", e)))?;
        let filename = filename_raw.trim_end_matches(' ').trim_end_matches('/');

        // File size: bytes 48..58, ASCII decimal, right-padded with spaces
        let size_str = std::str::from_utf8(&header[48..58])
            .map_err(|e| OilError::ParseError(format!("ar size field: {}", e)))?
            .trim();
        let size: u64 = size_str
            .parse()
            .map_err(|e| OilError::ParseError(format!("ar size '{}': {}", size_str, e)))?;

        // End magic: bytes 58..60 = "`\n"
        if &header[58..60] != b"`\n" {
            return Err(OilError::ParseError(
                "ar file header: missing end magic".to_string(),
            ));
        }

        if filename.starts_with("data.tar") {
            // This is the payload we want
            let compression = if filename.ends_with(".gz") {
                "gz"
            } else if filename.ends_with(".xz") {
                "xz"
            } else if filename.ends_with(".zst") {
                "zst"
            } else if filename.ends_with(".bz2") {
                "bz2"
            } else {
                "none"
            };

            extract_data_tar_untracked(&mut reader, size, compression, dest_dir)?;
            return Ok(());
        } else {
            // Skip this member; pad to even boundary
            let padded = size + (size & 1);
            reader.seek(SeekFrom::Current(padded as i64))?;
        }
    }

    Err(OilError::InstallError(
        "data.tar.* member not found in .deb archive".to_string(),
    ))
}

/// Extract a .deb package and return (files, dirs) of absolute paths written.
pub fn extract_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    std::fs::create_dir_all(dest_dir)?;
    let file = std::fs::File::open(path)?;
    let mut reader = std::io::BufReader::new(file);

    let mut global = [0u8; 8];
    reader.read_exact(&mut global)?;
    if &global != b"!<arch>\n" {
        return Err(OilError::InstallError(
            "Not a valid ar archive (missing global header)".to_string(),
        ));
    }

    loop {
        let mut header = [0u8; 60];
        match reader.read_exact(&mut header) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.into()),
        }

        let filename_raw = std::str::from_utf8(&header[0..16])
            .map_err(|e| OilError::ParseError(format!("ar filename: {}", e)))?;
        let filename = filename_raw.trim_end_matches(' ').trim_end_matches('/');

        let size_str = std::str::from_utf8(&header[48..58])
            .map_err(|e| OilError::ParseError(format!("ar size field: {}", e)))?
            .trim();
        let size: u64 = size_str
            .parse()
            .map_err(|e| OilError::ParseError(format!("ar size '{}': {}", size_str, e)))?;

        if &header[58..60] != b"`\n" {
            return Err(OilError::ParseError(
                "ar file header: missing end magic".to_string(),
            ));
        }

        if filename.starts_with("data.tar") {
            let compression = if filename.ends_with(".gz") {
                "gz"
            } else if filename.ends_with(".xz") {
                "xz"
            } else if filename.ends_with(".zst") {
                "zst"
            } else if filename.ends_with(".bz2") {
                "bz2"
            } else {
                "none"
            };

            return extract_data_tar_tracked(&mut reader, size, compression, dest_dir);
        } else {
            let padded = size + (size & 1);
            reader.seek(SeekFrom::Current(padded as i64))?;
        }
    }

    Err(OilError::InstallError(
        "data.tar.* member not found in .deb archive".to_string(),
    ))
}

#[allow(dead_code)]
fn extract_data_tar_untracked<R: Read>(
    reader: &mut R,
    size: u64,
    compression: &str,
    dest_dir: &Path,
) -> Result<()> {
    let (_, _) = extract_data_tar_inner(reader, size, compression, dest_dir)?;
    Ok(())
}

fn extract_data_tar_tracked<R: Read>(
    reader: &mut R,
    size: u64,
    compression: &str,
    dest_dir: &Path,
) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    extract_data_tar_inner(reader, size, compression, dest_dir)
}

fn extract_data_tar_inner<R: Read>(
    reader: &mut R,
    size: u64,
    compression: &str,
    dest_dir: &Path,
) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    // Read exactly `size` bytes into a buffer, then decompress
    let mut buf = vec![0u8; size as usize];
    reader.read_exact(&mut buf)?;

    match compression {
        "gz" => {
            let decoder = flate2::read::GzDecoder::new(&buf[..]);
            untar(decoder, dest_dir)
        }
        "xz" => {
            let decoder = xz2::read::XzDecoder::new(&buf[..]);
            untar(decoder, dest_dir)
        }
        "zst" => {
            let decoder = zstd::Decoder::new(&buf[..])
                .map_err(|e| OilError::InstallError(format!("zstd decoder error: {}", e)))?;
            untar(decoder, dest_dir)
        }
        "bz2" => {
            let decoder = bzip2::read::BzDecoder::new(&buf[..]);
            untar(decoder, dest_dir)
        }
        _ => {
            // No compression — raw tar
            untar(&buf[..], dest_dir)
        }
    }
}

fn untar<R: Read>(reader: R, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let mut archive = Archive::new(reader);
    let mut files = Vec::new();
    let mut dirs = Vec::new();

    for entry in archive.entries()? {
        let mut entry = entry?;
        let entry_path = entry.path()?;

        // Strip leading "./" and skip ".." entries
        let entry_str = entry_path.to_string_lossy();
        let stripped = if let Some(s) = entry_str.strip_prefix("./") {
            s.to_string()
        } else {
            entry_str.to_string()
        };

        if stripped.is_empty() || stripped.contains("..") {
            continue;
        }

        let dest = dest_dir.join(&stripped);

        if entry.header().entry_type().is_dir() {
            std::fs::create_dir_all(&dest)?;
            dirs.push(dest);
        } else if entry.header().entry_type().is_symlink() {
            if let Some(link_target) = entry.link_name()? {
                // Remove existing destination if any
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

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn make_ar_header(filename: &str, size: u64) -> Vec<u8> {
        let mut h = vec![0u8; 60];
        let fname = format!("{:<16}", filename);
        let size_str = format!("{:<10}", size);
        h[0..16].copy_from_slice(fname.as_bytes());
        h[16..28].copy_from_slice(b"0           "); // mtime
        h[28..34].copy_from_slice(b"0     "); // uid
        h[34..40].copy_from_slice(b"0     "); // gid
        h[40..48].copy_from_slice(b"100644  "); // mode
        h[48..58].copy_from_slice(size_str.as_bytes());
        h[58..60].copy_from_slice(b"`\n");
        h
    }

    fn make_test_deb() -> Vec<u8> {
        let mut data_tar = Vec::new();
        {
            let gz = flate2::write::GzEncoder::new(&mut data_tar, flate2::Compression::default());
            let mut tar = tar::Builder::new(gz);

            let content = b"hello from wax test\n";
            let mut header = tar::Header::new_gnu();
            header.set_path("usr/share/wax-test/hello.txt").unwrap();
            header.set_size(content.len() as u64);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append(&header, &content[..]).unwrap();
            tar.finish().unwrap();
        }

        let mut deb = Vec::new();
        deb.extend_from_slice(b"!<arch>\n");

        let debian_binary = b"2.0\n";
        deb.extend_from_slice(&make_ar_header("debian-binary", debian_binary.len() as u64));
        deb.extend_from_slice(debian_binary);
        if !debian_binary.len().is_multiple_of(2) {
            deb.push(b'\n');
        }

        deb.extend_from_slice(&make_ar_header("data.tar.gz", data_tar.len() as u64));
        deb.extend_from_slice(&data_tar);
        if data_tar.len() % 2 != 0 {
            deb.push(b'\n');
        }

        deb
    }

    #[test]
    fn test_extract_deb() {
        let tmp = TempDir::new().unwrap();
        let deb_path = tmp.path().join("test.deb");
        std::fs::write(&deb_path, make_test_deb()).unwrap();

        let dest = tmp.path().join("extracted");
        extract(&deb_path, &dest).unwrap();

        let hello = dest.join("usr/share/wax-test/hello.txt");
        assert!(hello.exists(), "extracted file should exist at {:?}", hello);
        assert_eq!(
            std::fs::read_to_string(&hello).unwrap(),
            "hello from wax test\n"
        );
    }

    #[test]
    fn test_extract_deb_tracked() {
        let tmp = TempDir::new().unwrap();
        let deb_path = tmp.path().join("test.deb");
        std::fs::write(&deb_path, make_test_deb()).unwrap();

        let dest = tmp.path().join("extracted");
        let (files, _dirs) = extract_tracked(&deb_path, &dest).unwrap();

        assert!(!files.is_empty());
        let hello = dest.join("usr/share/wax-test/hello.txt");
        assert!(files.contains(&hello));
    }

    #[test]
    fn test_invalid_deb_rejected() {
        let tmp = TempDir::new().unwrap();
        let bad_path = tmp.path().join("bad.deb");
        std::fs::write(&bad_path, b"not a deb file").unwrap();

        let dest = tmp.path().join("extracted");
        assert!(extract(&bad_path, &dest).is_err());
    }
}

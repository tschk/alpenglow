/// Extract an Alpine .apk package to dest_dir.
///
/// .apk files are concatenated gzip streams:
///   - Stream 1: tar with signature files (.SIGN.RSA.<key>, etc.)
///   - Stream 2: tar with control metadata (.PKGINFO, .INSTALL)
///   - Stream 3: tar with actual package data (what gets installed)
use std::io::Read;
use std::path::{Path, PathBuf};
use tar::Archive;

use crate::error::{OilError, Result};
use crate::system::verifier;

/// Try well-known Alpine public key paths. Returns the first PEM found.
fn find_apk_key(keyname: &str) -> Option<String> {
    let candidates = [
        format!("/etc/apk/keys/{keyname}.pub"),
        format!("/usr/share/apk/keys/{keyname}.pub"),
        format!("/etc/apk/keys/alpine-devel@lists.alpinelinux.org-{keyname}.pub"),
        format!("/etc/apk/keys/alpine-devel@lists.alpinelinux.org-{keyname}.pem"),
    ];
    for path in &candidates {
        if let Ok(pem) = std::fs::read_to_string(path) {
            if pem.contains("BEGIN") {
                return Some(pem);
            }
        }
    }
    None
}

/// Extract an APK package and return (files, dirs) of absolute paths written.
/// If no trusted key is found verification is skipped (degraded mode).
pub fn extract_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let data = std::fs::read(path)?;

    // Split into three gzip streams
    let streams = split_gzip_streams(&data, 3)?;

    // Try to verify signature from stream 1 against data tar (stream 3)
    let sig_keyname = extract_signature_info(&streams.0);
    if let Some((keyname, sig_bytes)) = sig_keyname {
        if let Some(pubkey_pem) = find_apk_key(&keyname) {
            eprintln!("Verifying APK signature (key: {keyname})...");
            verifier::verify_apk_signature(&streams.2, &sig_bytes, &pubkey_pem)
                .map_err(|e| OilError::Install(format!("signature verification failed: {e}")))?;
            eprintln!("Signature OK.");
        } else {
            eprintln!("Warning: no public key found for '{keyname}', skipping verification");
        }
    }

    // Extract data tar (stream 3) — this is what goes on disk
    std::fs::create_dir_all(dest_dir)?;
    untar(&streams.2, dest_dir)
}

/// Split a concatenated-gzip file into up to `count` individually
/// decompressed streams by scanning for gzip magic bytes.
fn split_gzip_streams(data: &[u8], count: usize) -> Result<(Vec<u8>, Vec<u8>, Vec<u8>)> {
    const MAX_STREAM_COUNT: usize = 3;
    const MAX_STREAM_SIZE: usize = 1024 * 1024 * 1024; // 1GB per stream
    const MAX_TOTAL_SIZE: usize = 2 * 1024 * 1024 * 1024; // 2GB total

    if count > MAX_STREAM_COUNT {
        return Err(OilError::Install(format!(
            "Requested {count} streams, maximum is {MAX_STREAM_COUNT}"
        )));
    }

    if data.len() > MAX_TOTAL_SIZE {
        return Err(OilError::Install(format!(
            "APK size {} exceeds maximum {}",
            data.len(),
            MAX_TOTAL_SIZE
        )));
    }

    let mut starts: Vec<usize> = Vec::new();
    let mut last_pos = 0;
    
    for i in 0..data.len().saturating_sub(1) {
        if data[i] == 0x1f && data[i + 1] == 0x8b {
            if i < last_pos {
                return Err(OilError::Install("Invalid gzip stream overlap".into()));
            }
            starts.push(i);
            last_pos = i;
            
            if starts.len() >= count {
                break;
            }
        }
    }
    
    if starts.len() < count {
        return Err(OilError::Install(format!(
            "APK has {} gzip streams, expected {count}",
            starts.len()
        )));
    }

    let mut out = Vec::with_capacity(count);
    let mut total_decompressed: usize = 0;
    
    for i in 0..count {
        let slice = &data[starts[i]..];
        let mut decoder = flate2::read::GzDecoder::new(slice);
        let mut buf = Vec::new();
        
        decoder.read_to_end(&mut buf)?;
        
        if buf.len() > MAX_STREAM_SIZE {
            return Err(OilError::Install(format!(
                "Stream {} size {} exceeds maximum {}",
                i,
                buf.len(),
                MAX_STREAM_SIZE
            )));
        }
        
        total_decompressed += buf.len();
        if total_decompressed > MAX_TOTAL_SIZE {
            return Err(OilError::Install(format!(
                "Total decompressed size {} exceeds maximum {}",
                total_decompressed,
                MAX_TOTAL_SIZE
            )));
        }
        
        out.push(buf);
    }
    
    Ok((out.remove(0), out.remove(0), out.remove(0)))
}

/// Extract the first `.SIGN.RSA.<keyname>` file from the signature tar
/// and return (keyname, raw CMS DER bytes).
fn extract_signature_info(tar_data: &[u8]) -> Option<(String, Vec<u8>)> {
    let mut archive = Archive::new(tar_data);
    for entry in archive.entries().ok()? {
        let mut entry = entry.ok()?;
        let name = entry.path().ok()?;
        let name_str = name.to_string_lossy();
        if let Some(rest) = name_str.strip_prefix(".SIGN.RSA.") {
            let keyname = rest.trim_end_matches('\0').to_string();
            let mut sig = Vec::new();
            entry.read_to_end(&mut sig).ok()?;
            return Some((keyname, sig));
        }
    }
    None
}

fn untar(tar_data: &[u8], dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let mut archive = Archive::new(tar_data);
    let mut files = Vec::new();
    let mut dirs = Vec::new();
    let mut entries_buf: Vec<Vec<u8>> = Vec::new();

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
        let mut archive = Archive::new(&data[..]);
        for entry_ in archive.entries()? {
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

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write;

    fn create_gzip_stream(content: &[u8]) -> Vec<u8> {
        let mut e = GzEncoder::new(Vec::new(), Compression::default());
        e.write_all(content).unwrap();
        e.finish().unwrap()
    }

    #[test]
    fn test_split_gzip_streams_happy_path() {
        let stream1 = create_gzip_stream(b"stream 1 data");
        let stream2 = create_gzip_stream(b"stream 2 data");
        let stream3 = create_gzip_stream(b"stream 3 data");

        let mut combined = Vec::new();
        combined.extend(&stream1);
        combined.extend(&stream2);
        combined.extend(&stream3);

        let result = split_gzip_streams(&combined, 3);
        assert!(result.is_ok());
        let (out1, out2, out3) = result.unwrap();

        assert_eq!(out1, b"stream 1 data");
        assert_eq!(out2, b"stream 2 data");
        assert_eq!(out3, b"stream 3 data");
    }

    #[test]
    fn test_split_gzip_streams_too_many_requested() {
        let stream = create_gzip_stream(b"data");
        let result = split_gzip_streams(&stream, 4);
        assert!(result.is_err());
        assert_eq!(
            result.unwrap_err().to_string(),
            "Requested 4 streams, maximum is 3"
        );
    }

    #[test]
    fn test_split_gzip_streams_not_enough_streams() {
        let stream1 = create_gzip_stream(b"data 1");
        let stream2 = create_gzip_stream(b"data 2");
        let mut combined = Vec::new();
        combined.extend(&stream1);
        combined.extend(&stream2);

        let result = split_gzip_streams(&combined, 3);
        assert!(result.is_err());
        assert_eq!(
            result.unwrap_err().to_string(),
            "APK has 2 gzip streams, expected 3"
        );
    }
}

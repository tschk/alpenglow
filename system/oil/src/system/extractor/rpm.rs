/// Extract an .rpm package to dest_dir.
///
/// Tries a pure-Rust RPM payload extractor first, then falls back to common
/// platform extraction tools when an RPM uses a payload shape Wax cannot parse.
use crate::error::{Result, OilError};
use std::collections::HashSet;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Extract an RPM and return newly-created files/symlinks and directories.
pub fn extract_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    if dest_dir == Path::new("/") {
        extract(path, dest_dir)?;
        return Ok((vec![], vec![]));
    }

    let before = snapshot_tree(dest_dir)?;
    extract(path, dest_dir)?;
    let after = snapshot_tree(dest_dir)?;

    let mut files = Vec::new();
    let mut dirs = Vec::new();
    for path in after.difference(&before) {
        let metadata = path.symlink_metadata()?;
        if metadata.is_dir() {
            dirs.push(path.clone());
        } else {
            files.push(path.clone());
        }
    }
    files.sort();
    dirs.sort();
    Ok((files, dirs))
}

pub fn extract(path: &Path, dest_dir: &Path) -> Result<()> {
    std::fs::create_dir_all(dest_dir)?;

    if extract_pure_rpm(path, dest_dir).is_ok() {
        return Ok(());
    }

    // Strategy 1: rpm2cpio + cpio
    if which_cmd("rpm2cpio") && which_cmd("cpio") {
        return extract_with_rpm2cpio(path, dest_dir);
    }

    // Strategy 2: bsdtar (libarchive can read RPMs directly)
    if which_cmd("bsdtar") {
        return extract_with_bsdtar(path, dest_dir);
    }

    // Strategy 3: rpm2archive + tar
    if which_cmd("rpm2archive") && which_cmd("tar") {
        return extract_with_rpm2archive(path, dest_dir);
    }

    Err(OilError::InstallError(format!(
        "RPM extraction requires one of the following tool chains:\n\
         • rpm2cpio + cpio   (install on Fedora/RHEL: rpm-cpio / cpio)\n\
         • bsdtar            (install on Debian/Ubuntu: libarchive-tools)\n\
         • rpm2archive + tar (install on Fedora/RHEL: rpm)\n\
         Package: {}",
        path.display()
    )))
}

fn extract_pure_rpm(path: &Path, dest_dir: &Path) -> Result<()> {
    let data = std::fs::read(path)?;
    if data.len() < 96 || data[0..4] != [0xed, 0xab, 0xee, 0xdb] {
        return Err(OilError::InstallError("not an rpm archive".to_string()));
    }

    let mut offset = 96usize;
    offset = skip_rpm_header(&data, offset)?;
    offset = skip_rpm_header(&data, offset)?;
    if offset >= data.len() {
        return Err(OilError::InstallError("rpm payload missing".to_string()));
    }

    let payload = decompress_payload(&data[offset..])?;
    extract_newc(&payload, dest_dir)
}

fn skip_rpm_header(data: &[u8], offset: usize) -> Result<usize> {
    if data.len() < offset + 16 || data[offset..offset + 3] != [0x8e, 0xad, 0xe8] {
        return Err(OilError::InstallError("rpm header missing".to_string()));
    }

    let count = u32::from_be_bytes([
        data[offset + 8],
        data[offset + 9],
        data[offset + 10],
        data[offset + 11],
    ]) as usize;
    let size = u32::from_be_bytes([
        data[offset + 12],
        data[offset + 13],
        data[offset + 14],
        data[offset + 15],
    ]) as usize;
    let end = offset
        .checked_add(16)
        .and_then(|v| v.checked_add(count.checked_mul(16)?))
        .and_then(|v| v.checked_add(size))
        .ok_or_else(|| OilError::InstallError("rpm header too large".to_string()))?;
    if end > data.len() {
        return Err(OilError::InstallError("rpm header truncated".to_string()));
    }

    Ok((end + 7) & !7)
}

fn decompress_payload(data: &[u8]) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    if data.starts_with(&[0x1f, 0x8b]) {
        let mut decoder = flate2::read::GzDecoder::new(data);
        decoder.read_to_end(&mut out)?;
        return Ok(out);
    }
    if data.starts_with(&[0xfd, b'7', b'z', b'X', b'Z', 0x00]) {
        let mut decoder = xz2::read::XzDecoder::new(data);
        decoder.read_to_end(&mut out)?;
        return Ok(out);
    }
    if data.starts_with(&[0x28, 0xb5, 0x2f, 0xfd]) {
        let mut decoder = zstd::Decoder::new(data).map_err(|e| {
            OilError::InstallError(format!("failed to read zstd rpm payload: {}", e))
        })?;
        decoder.read_to_end(&mut out)?;
        return Ok(out);
    }
    if data.starts_with(b"BZh") {
        let mut decoder = bzip2::read::BzDecoder::new(data);
        decoder.read_to_end(&mut out)?;
        return Ok(out);
    }
    if data.starts_with(b"070701") {
        return Ok(data.to_vec());
    }
    Err(OilError::InstallError(
        "unsupported rpm payload compression".to_string(),
    ))
}

fn extract_newc(data: &[u8], dest_dir: &Path) -> Result<()> {
    let mut cursor = Cursor::new(data);
    loop {
        let mut header = [0u8; 110];
        if cursor.read_exact(&mut header).is_err() {
            return Err(OilError::InstallError("truncated cpio header".to_string()));
        }
        if &header[0..6] != b"070701" {
            return Err(OilError::InstallError(
                "unsupported cpio format".to_string(),
            ));
        }

        let mode = read_hex(&header[14..22])?;
        let file_size = read_hex(&header[54..62])? as usize;
        let name_size = read_hex(&header[94..102])? as usize;
        if name_size == 0 {
            return Err(OilError::InstallError(
                "cpio entry missing name".to_string(),
            ));
        }

        let mut name_bytes = vec![0u8; name_size];
        cursor.read_exact(&mut name_bytes)?;
        align_cursor(&mut cursor, 4);
        if name_bytes.last() == Some(&0) {
            name_bytes.pop();
        }
        let name = String::from_utf8_lossy(&name_bytes);
        if name == "TRAILER!!!" {
            return Ok(());
        }

        let mut content = vec![0u8; file_size];
        cursor.read_exact(&mut content)?;
        align_cursor(&mut cursor, 4);

        let relative = safe_relative_path(&name);
        let Some(relative) = relative else {
            continue;
        };
        let target = dest_dir.join(relative);
        let kind = mode & 0o170000;
        match kind {
            0o040000 => {
                std::fs::create_dir_all(&target)?;
            }
            0o100000 => {
                if let Some(parent) = target.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                std::fs::write(&target, content)?;
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    let perms = std::fs::Permissions::from_mode(mode & 0o777);
                    std::fs::set_permissions(&target, perms)?;
                }
            }
            0o120000 => {
                if let Some(parent) = target.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                let link_target = String::from_utf8_lossy(&content);
                #[cfg(unix)]
                std::os::unix::fs::symlink(link_target.as_ref(), &target)?;
            }
            _ => {}
        }
    }
}

fn read_hex(bytes: &[u8]) -> Result<u32> {
    let text = std::str::from_utf8(bytes)
        .map_err(|e| OilError::InstallError(format!("invalid cpio header: {}", e)))?;
    u32::from_str_radix(text, 16)
        .map_err(|e| OilError::InstallError(format!("invalid cpio field: {}", e)))
}

fn align_cursor(cursor: &mut Cursor<&[u8]>, boundary: u64) {
    let pos = cursor.position();
    let aligned = (pos + boundary - 1) & !(boundary - 1);
    cursor.set_position(aligned);
}

fn safe_relative_path(name: &str) -> Option<PathBuf> {
    let path = Path::new(name.strip_prefix("./").unwrap_or(name));
    if path.is_absolute()
        || path
            .components()
            .any(|part| matches!(part, std::path::Component::ParentDir))
    {
        None
    } else {
        Some(path.to_path_buf())
    }
}

fn snapshot_tree(root: &Path) -> Result<HashSet<PathBuf>> {
    let mut paths = HashSet::new();
    if !root.exists() {
        return Ok(paths);
    }

    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir)? {
            let entry = entry?;
            let path = entry.path();
            let metadata = path.symlink_metadata()?;
            paths.insert(path.clone());
            if metadata.is_dir() {
                stack.push(path);
            }
        }
    }

    Ok(paths)
}

fn which_cmd(cmd: &str) -> bool {
    Command::new("which")
        .arg(cmd)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn extract_with_rpm2cpio(path: &Path, dest_dir: &Path) -> Result<()> {
    let rpm2cpio = Command::new("rpm2cpio")
        .arg(path)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| OilError::InstallError(format!("Failed to spawn rpm2cpio: {}", e)))?;

    let cpio_stdout = rpm2cpio
        .stdout
        .ok_or_else(|| OilError::InstallError("rpm2cpio stdout not available".to_string()))?;

    let output = Command::new("cpio")
        .args(["-idm", "--no-absolute-filenames"])
        .current_dir(dest_dir)
        .stdin(cpio_stdout)
        .output()
        .map_err(|e| OilError::InstallError(format!("Failed to run cpio: {}", e)))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(OilError::InstallError(format!(
            "cpio failed: {}",
            stderr.trim()
        )));
    }

    Ok(())
}

fn extract_with_bsdtar(path: &Path, dest_dir: &Path) -> Result<()> {
    let output = Command::new("bsdtar")
        .args(["-xf", &path.to_string_lossy()])
        .current_dir(dest_dir)
        .output()
        .map_err(|e| OilError::InstallError(format!("Failed to run bsdtar: {}", e)))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(OilError::InstallError(format!(
            "bsdtar failed: {}",
            stderr.trim()
        )));
    }

    Ok(())
}

fn extract_with_rpm2archive(path: &Path, dest_dir: &Path) -> Result<()> {
    // Fedora's rpm2archive writes the compressed archive to stdout, so stream it
    // directly into tar instead of expecting a sidecar archive file.
    let mut rpm2archive = Command::new("rpm2archive")
        .arg(path)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| OilError::InstallError(format!("Failed to spawn rpm2archive: {}", e)))?;

    let archive_stdout = rpm2archive
        .stdout
        .take()
        .ok_or_else(|| OilError::InstallError("rpm2archive stdout not available".to_string()))?;

    let tar_output = Command::new("tar")
        .args(["-xzf", "-"])
        .current_dir(dest_dir)
        .stdin(archive_stdout)
        .output()
        .map_err(|e| OilError::InstallError(format!("Failed to run tar: {}", e)))?;

    let rpm2archive_output = rpm2archive
        .wait_with_output()
        .map_err(|e| OilError::InstallError(format!("Failed to wait for rpm2archive: {}", e)))?;

    if !rpm2archive_output.status.success() {
        let stderr = String::from_utf8_lossy(&rpm2archive_output.stderr);
        return Err(OilError::InstallError(format!(
            "rpm2archive failed: {}",
            stderr.trim()
        )));
    }

    if !tar_output.status.success() {
        let stderr = String::from_utf8_lossy(&tar_output.stderr);
        return Err(OilError::InstallError(format!(
            "tar failed: {}",
            stderr.trim()
        )));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write;
    use tempfile::TempDir;

    fn rpm_header() -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&[0x8e, 0xad, 0xe8, 0x01]);
        bytes.extend_from_slice(&[0, 0, 0, 0]);
        bytes.extend_from_slice(&0u32.to_be_bytes());
        bytes.extend_from_slice(&0u32.to_be_bytes());
        bytes
    }

    fn newc_entry(name: &str, mode: u32, content: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        let name_size = name.len() + 1;
        out.extend_from_slice(
            format!(
                "070701{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}",
                0, mode, 0, 0, 1, 0, content.len(), 0, 0, 0, 0, name_size, 0
            )
            .as_bytes(),
        );
        out.extend_from_slice(name.as_bytes());
        out.push(0);
        while out.len() % 4 != 0 {
            out.push(0);
        }
        out.extend_from_slice(content);
        while out.len() % 4 != 0 {
            out.push(0);
        }
        out
    }

    fn test_rpm() -> Vec<u8> {
        let mut cpio = Vec::new();
        cpio.extend(newc_entry("usr", 0o040755, b""));
        cpio.extend(newc_entry("usr/bin", 0o040755, b""));
        cpio.extend(newc_entry("usr/bin/hello", 0o100755, b"hello\n"));
        cpio.extend(newc_entry("TRAILER!!!", 0, b""));

        let mut gz = GzEncoder::new(Vec::new(), Compression::default());
        gz.write_all(&cpio).unwrap();
        let payload = gz.finish().unwrap();

        let mut rpm = vec![0u8; 96];
        rpm[0..4].copy_from_slice(&[0xed, 0xab, 0xee, 0xdb]);
        rpm.extend(rpm_header());
        rpm.extend(rpm_header());
        rpm.extend(payload);
        rpm
    }

    #[test]
    fn pure_rpm_extractor_extracts_gzipped_newc_payload() {
        let temp = TempDir::new().unwrap();
        let rpm_path = temp.path().join("test.rpm");
        let dest = temp.path().join("root");
        std::fs::write(&rpm_path, test_rpm()).unwrap();

        extract_pure_rpm(&rpm_path, &dest).unwrap();

        assert_eq!(
            std::fs::read_to_string(dest.join("usr/bin/hello")).unwrap(),
            "hello\n"
        );
    }
}

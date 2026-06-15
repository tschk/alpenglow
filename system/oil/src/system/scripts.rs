use crate::error::{Result, OilError};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::process::Command;
use tempfile::NamedTempFile;

pub fn run_post_install_script(package_path: &Path, prefix: &Path) -> Result<()> {
    let name = package_path.to_string_lossy();
    let script = if name.ends_with(".deb") {
        deb_postinst(package_path)?
    } else if name.ends_with(".rpm") {
        rpm_postinstall(package_path)?
    } else {
        None
    };

    let Some(script) = script else {
        return Ok(());
    };

    if script.trim().is_empty() {
        return Ok(());
    }

    run_shell_script(&script, prefix)
}

fn run_shell_script(script: &str, prefix: &Path) -> Result<()> {
    let mut file = NamedTempFile::new()
        .map_err(|e| OilError::InstallError(format!("create post-install script: {e}")))?;
    file.write_all(script.as_bytes())
        .map_err(|e| OilError::InstallError(format!("write post-install script: {e}")))?;
    file.flush()
        .map_err(|e| OilError::InstallError(format!("flush post-install script: {e}")))?;

    let status = Command::new("sh")
        .arg("-e")
        .arg(file.path())
        .arg("configure")
        .current_dir(prefix)
        .env("WAX_INSTALL_PREFIX", prefix)
        .env("WAX_ROOT", prefix)
        .status()
        .map_err(|e| OilError::InstallError(format!("run post-install script: {e}")))?;

    if !status.success() {
        return Err(OilError::InstallError(format!(
            "post-install script failed with status {}",
            status.code().unwrap_or(-1)
        )));
    }

    Ok(())
}

fn deb_postinst(path: &Path) -> Result<Option<String>> {
    let file = std::fs::File::open(path)?;
    let mut reader = std::io::BufReader::new(file);

    let mut global = [0u8; 8];
    reader.read_exact(&mut global)?;
    if &global != b"!<arch>\n" {
        return Err(OilError::InstallError(
            "not a valid .deb archive (missing ar header)".to_string(),
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
            .map_err(|e| OilError::ParseError(format!("ar filename: {e}")))?;
        let filename = filename_raw.trim_end_matches(' ').trim_end_matches('/');
        let size_str = std::str::from_utf8(&header[48..58])
            .map_err(|e| OilError::ParseError(format!("ar size field: {e}")))?
            .trim();
        let size: u64 = size_str
            .parse()
            .map_err(|e| OilError::ParseError(format!("ar size '{size_str}': {e}")))?;

        if &header[58..60] != b"`\n" {
            return Err(OilError::ParseError(
                "ar file header: missing end magic".to_string(),
            ));
        }

        if filename.starts_with("control.tar") {
            let compression = compression_from_tar_name(filename);
            let mut buf = vec![0u8; size as usize];
            reader.read_exact(&mut buf)?;
            return postinst_from_control_tar(&buf, compression);
        }

        let padded = size + (size & 1);
        reader.seek(SeekFrom::Current(padded as i64))?;
    }

    Ok(None)
}

fn compression_from_tar_name(filename: &str) -> &str {
    if filename.ends_with(".gz") {
        "gz"
    } else if filename.ends_with(".xz") {
        "xz"
    } else if filename.ends_with(".zst") {
        "zst"
    } else if filename.ends_with(".bz2") {
        "bz2"
    } else {
        "none"
    }
}

fn postinst_from_control_tar(buf: &[u8], compression: &str) -> Result<Option<String>> {
    match compression {
        "gz" => read_postinst_from_tar(flate2::read::GzDecoder::new(buf)),
        "xz" => read_postinst_from_tar(xz2::read::XzDecoder::new(buf)),
        "zst" => {
            let decoder = zstd::Decoder::new(buf)
                .map_err(|e| OilError::InstallError(format!("zstd decoder error: {e}")))?;
            read_postinst_from_tar(decoder)
        }
        "bz2" => read_postinst_from_tar(bzip2::read::BzDecoder::new(buf)),
        "none" => read_postinst_from_tar(buf),
        other => Err(OilError::InstallError(format!(
            "unsupported control.tar compression: {other}"
        ))),
    }
}

fn read_postinst_from_tar<R: Read>(reader: R) -> Result<Option<String>> {
    let mut archive = tar::Archive::new(reader);
    for entry in archive.entries()? {
        let mut entry = entry?;
        let path = entry.path()?.to_string_lossy().to_string();
        if path == "postinst" || path == "./postinst" {
            let mut script = String::new();
            entry.read_to_string(&mut script)?;
            return Ok(Some(script));
        }
    }
    Ok(None)
}

fn rpm_postinstall(path: &Path) -> Result<Option<String>> {
    let output = Command::new("rpm")
        .args(["-qp", "--scripts"])
        .arg(path)
        .output()
        .map_err(|e| OilError::InstallError(format!("extract rpm scripts: {e}")))?;

    if !output.status.success() {
        return Err(OilError::InstallError(format!(
            "rpm script metadata extraction failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }

    let scripts = String::from_utf8_lossy(&output.stdout);
    Ok(extract_rpm_scriptlet(&scripts, "postinstall"))
}

fn extract_rpm_scriptlet(scripts: &str, wanted: &str) -> Option<String> {
    let mut in_wanted = false;
    let mut body = Vec::new();

    for line in scripts.lines() {
        if is_rpm_scriptlet_header(line) {
            if in_wanted {
                break;
            }
            in_wanted = line.starts_with(wanted);
            continue;
        }

        if in_wanted {
            body.push(line);
        }
    }

    if body.is_empty() {
        None
    } else {
        Some(body.join("\n"))
    }
}

fn is_rpm_scriptlet_header(line: &str) -> bool {
    [
        "preinstall scriptlet",
        "postinstall scriptlet",
        "preuninstall scriptlet",
        "postuninstall scriptlet",
        "pretrans scriptlet",
        "posttrans scriptlet",
        "verify scriptlet",
    ]
    .iter()
    .any(|prefix| line.starts_with(prefix))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_rpm_postinstall_scriptlet() {
        let scripts = "preinstall scriptlet (using /bin/sh):\necho pre\npostinstall scriptlet (using /bin/sh):\necho post\nldconfig\npostuninstall scriptlet (using /bin/sh):\necho bye\n";
        assert_eq!(
            extract_rpm_scriptlet(scripts, "postinstall").as_deref(),
            Some("echo post\nldconfig")
        );
    }

    #[test]
    fn test_extract_rpm_postinstall_missing() {
        let scripts = "preinstall scriptlet (using /bin/sh):\necho pre\n";
        assert!(extract_rpm_scriptlet(scripts, "postinstall").is_none());
    }
}

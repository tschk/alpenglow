/// Nix Archive (NAR) extractor.
///
/// NAR is the native archive format for Nix store paths.
/// Each archive is a tree of entries (directories, files, symlinks).
/// Strings are length-prefixed: [8 bytes BE length][data].
/// Integers are: [8 bytes BE value].
use crate::error::{Result, OilError};
use std::io::Read;
use std::path::{Path, PathBuf};

/// Extract a .nar or .nar.zst file to dest_dir.
pub fn extract_nar_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let data = std::fs::read(path)?;
    // Check if zstd compressed
    if path.extension().map(|e| e == "zst").unwrap_or(false) || data.starts_with(&[0x28, 0xb5, 0x2f, 0xfd]) {
        let mut decoder = zstd::Decoder::new(&data[..])
            .map_err(|e| OilError::InstallError(format!("zstd decompress: {}", e)))?;
        let mut decompressed = Vec::new();
        decoder.read_to_end(&mut decompressed)
            .map_err(|e| OilError::InstallError(format!("zstd read: {}", e)))?;
        return extract_nar(&decompressed, dest_dir);
    }
    extract_nar(&data, dest_dir)
}

pub fn extract_nar(data: &[u8], dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    std::fs::create_dir_all(dest_dir)?;
    let mut pos = 0usize;
    let mut files = Vec::new();
    let mut dirs = Vec::new();

    // Skip 8-byte padding/header
    pos += 8;

    // Parse the top-level entry (must be a directory representing the store path root)
    parse_entry(data, &mut pos, dest_dir, &mut files, &mut dirs)?;

    Ok((files, dirs))
}

fn parse_entry(data: &[u8], pos: &mut usize, dest_dir: &Path, files: &mut Vec<PathBuf>, dirs: &mut Vec<PathBuf>) -> Result<usize> {
    if *pos >= data.len() {
        return Err(OilError::InstallError("NAR: unexpected EOF at entry start".into()));
    }

    // Each entry starts with a parenthesis
    if data[*pos] != b'(' {
        return Err(OilError::InstallError(format!("NAR: expected '(' at offset {}, got {:02x}", pos, data[*pos])));
    }
    *pos += 1;

    // Token type
    let typ = read_token(data, pos)?;
    let consumed = match typ.as_str() {
        "type" => {
            let entry_type = read_token(data, pos)?;
            match entry_type.as_str() {
                "directory" => parse_directory(data, pos, dest_dir, files, dirs)?,
                "regular" => parse_regular(data, pos, dest_dir, files, dirs)?,
                "symlink" => parse_symlink(data, pos, dest_dir, files)?,
                other => return Err(OilError::InstallError(format!("NAR: unknown entry type: {}", other))),
            }
        }
        other => return Err(OilError::InstallError(format!("NAR: expected 'type' token, got '{}'", other))),
    };

    // Closing paren
    if *pos >= data.len() || data[*pos] != b')' {
        return Err(OilError::InstallError("NAR: expected ')' at end of entry".into()));
    }
    *pos += 1;

    Ok(consumed)
}

fn parse_directory(data: &[u8], pos: &mut usize, base: &Path, files: &mut Vec<PathBuf>, dirs: &mut Vec<PathBuf>) -> Result<usize> {
    let mut name = String::new();
    let mut entries_consumed = 0;

    loop {
        if *pos >= data.len() {
            return Err(OilError::InstallError("NAR: unexpected EOF in directory".into()));
        }
        // Check for closing paren (end of directory)
        if data[*pos] == b')' {
            break;
        }

        let token = read_token(data, pos)?;
        match token.as_str() {
            "name" => {
                name = read_token(data, pos)?;
            }
            "entries" => {
                // Child entries
                loop {
                    if *pos >= data.len() {
                        return Err(OilError::InstallError("NAR: unexpected EOF in directory entries".into()));
                    }
                    if data[*pos] == b')' {
                        break; // end of entries
                    }
                    entries_consumed += parse_entry(data, pos, &base.join(&name), files, dirs)?;
                }
                if *pos < data.len() && data[*pos] == b')' {
                    *pos += 1; // consume entries closing paren
                }
            }
            "target" | "contents" | "permissions" => {
                // These shouldn't appear in directory entries
                skip_token(data, pos)?;
            }
            _ => {
                skip_token(data, pos)?;
            }
        }
    }

    Ok(entries_consumed)
}

fn parse_regular(data: &[u8], pos: &mut usize, base: &Path, files: &mut Vec<PathBuf>, _dirs: &mut Vec<PathBuf>) -> Result<usize> {
    let mut name = String::new();
    let mut contents = Vec::new();
    let mut _permissions = 0u64;

    loop {
        if *pos >= data.len() {
            return Err(OilError::InstallError("NAR: unexpected EOF in regular file".into()));
        }
        if data[*pos] == b')' {
            break;
        }

        let token = read_token(data, pos)?;
        match token.as_str() {
            "name" => name = read_token(data, pos)?,
            "contents" => {
                let size = read_int(data, pos)? as usize;
                if *pos + size > data.len() {
                    return Err(OilError::InstallError("NAR: file contents exceed data size".into()));
                }
                contents = data[*pos..*pos + size].to_vec();
                *pos += size;
                // Padding to 8-byte boundary
                let pad = (8 - (size % 8)) % 8;
                *pos += pad;
            }
            "permissions" => _permissions = read_int(data, pos)?,
            _ => { skip_token(data, pos)?; }
        }
    }

    // Write the file
    let dest = base.join(&name);
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&dest, &contents)?;
    files.push(dest);

    Ok(1)
}

fn parse_symlink(data: &[u8], pos: &mut usize, base: &Path, files: &mut Vec<PathBuf>) -> Result<usize> {
    let mut name = String::new();
    let mut target = String::new();

    loop {
        if *pos >= data.len() {
            return Err(OilError::InstallError("NAR: unexpected EOF in symlink".into()));
        }
        if data[*pos] == b')' {
            break;
        }

        let token = read_token(data, pos)?;
        match token.as_str() {
            "name" => name = read_token(data, pos)?,
            "target" => target = read_token(data, pos)?,
            _ => { skip_token(data, pos)?; }
        }
    }

    let dest = base.join(&name);
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)?;
    }
    #[cfg(unix)]
    std::os::unix::fs::symlink(&target, &dest)?;
    files.push(dest);

    Ok(1)
}

/// Read a length-prefixed token/string from the data stream.
fn read_token(data: &[u8], pos: &mut usize) -> Result<String> {
    let len = read_int(data, pos)? as usize;
    if *pos + len > data.len() {
        return Err(OilError::InstallError("NAR: token exceeds data size".into()));
    }
    let s = String::from_utf8_lossy(&data[*pos..*pos + len]).to_string();
    *pos += len;
    Ok(s)
}

/// Read an 8-byte big-endian integer.
fn read_int(data: &[u8], pos: &mut usize) -> Result<u64> {
    if *pos + 8 > data.len() {
        return Err(OilError::InstallError("NAR: unexpected EOF reading int".into()));
    }
    let bytes: [u8; 8] = data[*pos..*pos + 8].try_into().unwrap();
    *pos += 8;
    Ok(u64::from_be_bytes(bytes))
}

/// Skip a length-prefixed token.
fn skip_token(data: &[u8], pos: &mut usize) -> Result<()> {
    let len = read_int(data, pos)? as usize;
    if *pos + len > data.len() {
        return Err(OilError::InstallError("NAR: skip exceeds data size".into()));
    }
    *pos += len;
    Ok(())
}

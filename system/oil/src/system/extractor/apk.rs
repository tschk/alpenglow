/// Extract an Alpine .apk package to dest_dir.
///
/// .apk files are concatenated gzip members:
///   - Member 1: tar with signature files (.SIGN.RSA.<key> / .SIGN.RSA256.<key>)
///   - Member 2: tar with control metadata (.PKGINFO, .INSTALL)
///   - Member 3: tar with actual package data (what gets installed)
///
/// The signature covers the compressed control member; `.PKGINFO`'s
/// `datahash` covers the compressed data member (see `system::verifier`).
use std::io::Read;
use std::ops::Range;
use std::path::{Path, PathBuf};
use tar::Archive;

use crate::error::{OilError, Result};
use crate::system::verifier::{self, SigHash};

/// Alpine's release signing keys (alpine-keys 2.4, cross-checked against
/// aports main/alpine-keys). Keys in /etc/apk/keys and /usr/share/apk/keys
/// are trusted too, so taps can add their own.
macro_rules! alpine_key {
    ($id:literal) => {
        (
            concat!("alpine-devel@lists.alpinelinux.org-", $id, ".rsa.pub"),
            include_str!(concat!(
                "../../../keys/alpine-devel@lists.alpinelinux.org-",
                $id,
                ".rsa.pub"
            )),
        )
    };
}

const BUILTIN_KEYS: &[(&str, &str)] = &[
    alpine_key!("4a6a0840"),
    alpine_key!("5243ef4b"),
    alpine_key!("524d27bb"),
    alpine_key!("5261cecb"),
    alpine_key!("58199dcc"),
    alpine_key!("58cbb476"),
    alpine_key!("58e4f17d"),
    alpine_key!("5e69ca50"),
    alpine_key!("60ac2099"),
    alpine_key!("6165ee59"),
    alpine_key!("61666e3f"),
    alpine_key!("616a9724"),
    alpine_key!("616abc23"),
    alpine_key!("616ac3bc"),
    alpine_key!("616adfeb"),
    alpine_key!("616ae350"),
    alpine_key!("616db30d"),
];

fn is_safe_apk_keyname(keyname: &str) -> bool {
    !keyname.is_empty()
        && !keyname.contains('/')
        && !keyname.contains('\\')
        && !keyname.contains('\0')
        && Path::new(keyname)
            .components()
            .all(|c| matches!(c, std::path::Component::Normal(_)))
}

/// Look up a public key by its exact filename, as apk-tools does.
fn find_apk_key_in_root(root: &Path, keyname: &str) -> Option<String> {
    if !is_safe_apk_keyname(keyname) {
        return None;
    }
    for dir in ["etc/apk/keys", "usr/share/apk/keys"] {
        if let Ok(pem) = std::fs::read_to_string(root.join(dir).join(keyname)) {
            if pem.contains("BEGIN") {
                return Some(pem);
            }
        }
    }
    BUILTIN_KEYS
        .iter()
        .find(|(name, _)| *name == keyname)
        .map(|(_, pem)| (*pem).to_string())
}

/// Extract an APK package and return (files, dirs) of absolute paths written.
pub fn extract_tracked(path: &Path, dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    extract_tracked_with_keys(path, dest_dir, Path::new("/"))
}

fn extract_tracked_with_keys(
    path: &Path,
    dest_dir: &Path,
    key_root: &Path,
) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    const MAX_APK_SIZE: u64 = 2 * 1024 * 1024 * 1024;
    if std::fs::metadata(path)?.len() > MAX_APK_SIZE {
        return Err(OilError::Install(format!(
            "APK size exceeds maximum {MAX_APK_SIZE}"
        )));
    }
    let data = std::fs::read(path)?;
    let members = split_gzip_members(&data)?;
    let data_tar = verify_package(&data, &members, key_root)?;

    // Extract the data tar — this is what goes on disk
    std::fs::create_dir_all(dest_dir)?;
    untar(data_tar, dest_dir)
}

/// One gzip member: its compressed byte range in the file and its contents.
struct Member {
    raw: Range<usize>,
    tar: Vec<u8>,
}

/// Verify signature and datahash; return the data tar to extract.
fn verify_package<'a>(data: &[u8], members: &'a [Member], key_root: &Path) -> Result<&'a [u8]> {
    let insecure = crate::util::security::insecure_mode();
    let signatures = match members.len() {
        3 => extract_signatures(&members[0].tar),
        _ => Vec::new(),
    };
    let data_member = members
        .last()
        .ok_or_else(|| OilError::Install("APK has no gzip members".into()))?;
    if signatures.is_empty() {
        if insecure {
            eprintln!("Warning: unsigned APK, skipping verification");
            return Ok(&data_member.tar);
        }
        return Err(OilError::Install(
            "APK has no signature stream; set OIL_INSECURE_NO_VERIFY=1 to override".into(),
        ));
    }

    let control = &members[1];
    let control_raw = &data[control.raw.clone()];
    let mut last_err = None;
    let mut verified_with = None;
    for (keyname, hash, sig) in &signatures {
        let Some(pem) = find_apk_key_in_root(key_root, keyname) else {
            last_err = Some(OilError::Install(format!(
                "no public key found for '{keyname}'"
            )));
            continue;
        };
        match verifier::verify_rsa_signature(control_raw, sig, *hash, &pem) {
            Ok(()) => {
                verified_with = Some(keyname.clone());
                break;
            }
            Err(e) => last_err = Some(e),
        }
    }
    let Some(keyname) = verified_with else {
        let err = last_err.unwrap_or_else(|| OilError::Install("no usable signature".into()));
        if insecure {
            eprintln!("Warning: {err}; skipping verification");
            return Ok(&data_member.tar);
        }
        return Err(OilError::Install(format!(
            "signature verification failed: {err}; set OIL_INSECURE_NO_VERIFY=1 to override"
        )));
    };

    // The signature authenticates the control member; .PKGINFO's datahash
    // then authenticates the data member. Without it the payload is unbound.
    let datahash = pkginfo_value(&control.tar, "datahash")
        .ok_or_else(|| OilError::Install("signed APK has no datahash in .PKGINFO".into()))?;
    verifier::verify_datahash(&data[data_member.raw.clone()], &datahash)
        .map_err(|e| OilError::Install(format!("data verification failed: {e}")))?;
    eprintln!("Signature OK (key: {keyname}).");
    Ok(&data_member.tar)
}

/// Split a concatenated-gzip file into its members, decompressing each and
/// recording the exact compressed byte range it occupies.
fn split_gzip_members(data: &[u8]) -> Result<Vec<Member>> {
    const MAX_STREAM_SIZE: usize = 1024 * 1024 * 1024; // 1GB per member
    const MAX_TOTAL_SIZE: usize = 2 * 1024 * 1024 * 1024; // 2GB total
    split_gzip_members_with_limits(data, MAX_STREAM_SIZE, MAX_TOTAL_SIZE)
}

fn split_gzip_members_with_limits(
    data: &[u8],
    max_stream_size: usize,
    max_total_size: usize,
) -> Result<Vec<Member>> {
    const MAX_MEMBERS: usize = 3;

    if data.len() > max_total_size {
        return Err(OilError::Install(format!(
            "APK size {} exceeds maximum {}",
            data.len(),
            max_total_size
        )));
    }

    let mut members = Vec::new();
    let mut offset = 0;
    let mut total_decompressed: usize = 0;
    while offset < data.len() {
        if members.len() == MAX_MEMBERS {
            return Err(OilError::Install(format!(
                "APK has more than {MAX_MEMBERS} gzip members"
            )));
        }
        let i = members.len();
        let rest = &data[offset..];
        let mut decoder = flate2::bufread::GzDecoder::new(rest);
        let remaining = max_total_size - total_decompressed;
        let allowed = max_stream_size.min(remaining);
        let mut buf = Vec::new();
        decoder
            .by_ref()
            .take(allowed as u64 + 1)
            .read_to_end(&mut buf)
            .map_err(|e| OilError::Install(format!("gzip member {i}: {e}")))?;

        if buf.len() > max_stream_size {
            return Err(OilError::Install(format!(
                "Stream {} size {} exceeds maximum {}",
                i,
                buf.len(),
                max_stream_size
            )));
        }
        if buf.len() > remaining {
            return Err(OilError::Install(format!(
                "Total decompressed size {} exceeds maximum {}",
                total_decompressed + buf.len(),
                max_total_size
            )));
        }
        total_decompressed += buf.len();

        // bufread::GzDecoder stops at the end of one member's trailer.
        let consumed = rest.len() - decoder.into_inner().len();
        if consumed == 0 {
            return Err(OilError::Install(format!("empty gzip member {i}")));
        }
        members.push(Member {
            raw: offset..offset + consumed,
            tar: buf,
        });
        offset += consumed;
    }

    if members.len() < 2 {
        return Err(OilError::Install(format!(
            "APK has {} gzip members, expected 3",
            members.len()
        )));
    }
    Ok(members)
}

/// Every `.SIGN.RSA.<key>` (SHA-1) and `.SIGN.RSA256.<key>` (SHA-256) entry.
fn extract_signatures(tar_data: &[u8]) -> Vec<(String, SigHash, Vec<u8>)> {
    let mut out = Vec::new();
    let mut archive = Archive::new(tar_data);
    let Ok(entries) = archive.entries() else {
        return out;
    };
    for entry in entries {
        let Ok(mut entry) = entry else { break };
        let path = entry.path_bytes().into_owned();
        let (hash, rest) = if let Some(rest) = path.strip_prefix(b".SIGN.RSA256.") {
            (SigHash::Sha256, rest)
        } else if let Some(rest) = path.strip_prefix(b".SIGN.RSA.") {
            (SigHash::Sha1, rest)
        } else {
            continue;
        };
        let keyname = String::from_utf8_lossy(rest)
            .trim_end_matches('\0')
            .to_string();
        let mut sig = Vec::new();
        if entry.read_to_end(&mut sig).is_ok() {
            out.push((keyname, hash, sig));
        }
    }
    out
}

/// Read `key = value` from the control tar's .PKGINFO.
fn pkginfo_value(control_tar: &[u8], key: &str) -> Option<String> {
    let mut archive = Archive::new(control_tar);
    for entry in archive.entries().ok()? {
        let mut entry = entry.ok()?;
        if entry.path_bytes().as_ref() != b".PKGINFO" {
            continue;
        }
        let mut text = String::new();
        entry.read_to_string(&mut text).ok()?;
        return text.lines().find_map(|line| {
            let (k, v) = line.split_once(" = ")?;
            (k.trim() == key).then(|| v.trim().to_string())
        });
    }
    None
}

fn is_safe_symlink(link_target: &Path, dest: &Path, dest_dir: &Path) -> bool {
    if link_target.is_absolute() {
        return false;
    }

    let mut resolved = dest.parent().unwrap_or_else(|| Path::new("")).to_path_buf();

    for comp in link_target.components() {
        match comp {
            std::path::Component::ParentDir => {
                if !resolved.pop() {
                    return false;
                }
                if !resolved.starts_with(dest_dir) {
                    return false;
                }
            }
            std::path::Component::Normal(c) => {
                resolved.push(c);
            }
            _ => continue,
        }
    }

    resolved.starts_with(dest_dir)
}

fn process_tar_entry<R: std::io::Read>(
    mut entry: tar::Entry<'_, R>,
    dest_dir: &Path,
    files: &mut Vec<PathBuf>,
    dirs: &mut Vec<PathBuf>,
    created_dirs: &mut std::collections::HashSet<PathBuf>,
) -> Result<()> {
    let entry_path = entry.path()?;
    let entry_str = entry_path.to_string_lossy();

    if entry_str == ".PKGINFO" || entry_str == ".INSTALL" || entry_str.starts_with(".SIGN.") {
        return Ok(());
    }

    let stripped = entry_str
        .strip_prefix("./")
        .unwrap_or(entry_str.as_ref())
        .trim_start_matches('/');
    if stripped.is_empty() || stripped.contains("..") {
        return Ok(());
    }

    let dest = dest_dir.join(stripped);
    if let Some(parent) = dest.parent() {
        if !created_dirs.contains(parent) {
            std::fs::create_dir_all(parent)?;
            let mut current = parent;
            while !created_dirs.contains(current) {
                created_dirs.insert(current.to_path_buf());
                current = match current.parent() {
                    Some(p) => p,
                    None => break,
                };
            }
        }
    }

    let kind = entry.header().entry_type();
    if kind.is_dir() {
        process_dir(&dest, dirs, created_dirs)?;
    } else if kind.is_symlink() {
        process_symlink(&entry, &dest, dest_dir, files)?;
    } else if kind.is_hard_link() {
        return Err(OilError::Install(format!(
            "hard links are not allowed in APK payloads: {stripped}"
        )));
    } else if kind.is_file() {
        process_file(&mut entry, &dest, files)?;
    } else {
        return Err(OilError::Install(format!(
            "unsupported tar entry type for {stripped}"
        )));
    }

    Ok(())
}

fn process_dir(
    dest: &Path,
    dirs: &mut Vec<PathBuf>,
    created_dirs: &mut std::collections::HashSet<PathBuf>,
) -> Result<()> {
    if !created_dirs.contains(dest) {
        std::fs::create_dir_all(dest)?;
        created_dirs.insert(dest.to_path_buf());
    }
    dirs.push(dest.to_path_buf());
    Ok(())
}

fn process_symlink<R: std::io::Read>(
    entry: &tar::Entry<'_, R>,
    dest: &Path,
    dest_dir: &Path,
    files: &mut Vec<PathBuf>,
) -> Result<()> {
    if let Some(link_target) = entry.link_name()? {
        if !is_safe_symlink(link_target.as_ref(), dest, dest_dir) {
            return Err(OilError::Install(format!(
                "Unsafe symlink target {:?} for {:?}",
                link_target, dest
            )));
        }
        let _ = std::fs::remove_file(dest);
        let _ = std::fs::remove_dir_all(dest);
        #[cfg(unix)]
        std::os::unix::fs::symlink(link_target.as_ref(), dest)?;
        files.push(dest.to_path_buf());
    }
    Ok(())
}

fn process_file<R: std::io::Read>(
    entry: &mut tar::Entry<'_, R>,
    dest: &Path,
    files: &mut Vec<PathBuf>,
) -> Result<()> {
    entry.unpack(dest)?;
    files.push(dest.to_path_buf());
    Ok(())
}

fn untar(tar_data: &[u8], dest_dir: &Path) -> Result<(Vec<PathBuf>, Vec<PathBuf>)> {
    let mut archive = Archive::new(tar_data);
    let mut files = Vec::new();
    let mut dirs = Vec::new();
    let mut created_dirs = std::collections::HashSet::new();
    created_dirs.insert(dest_dir.to_path_buf());

    for entry_result in archive.entries()? {
        let entry = entry_result?;
        process_tar_entry(entry, dest_dir, &mut files, &mut dirs, &mut created_dirs)?;
    }

    Ok((files, dirs))
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write;
    use tempfile::tempdir;

    type TestResult = std::result::Result<(), Box<dyn std::error::Error>>;

    /// alpine-keys 2.4-r1 for x86_64, byte-for-byte from dl-cdn v3.20/main,
    /// signed by alpine-devel@lists.alpinelinux.org-6165ee59.rsa.pub.
    const REAL_APK: &[u8] = include_bytes!("../../../tests/fixtures/alpine-keys-2.4-r1.apk");
    const REAL_KEY: &str = "alpine-devel@lists.alpinelinux.org-6165ee59.rsa.pub";

    fn create_gz_stream(data: &[u8]) -> std::result::Result<Vec<u8>, Box<dyn std::error::Error>> {
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(data)?;
        Ok(encoder.finish()?)
    }

    fn tar_with(
        name: &str,
        body: &[u8],
    ) -> std::result::Result<Vec<u8>, Box<dyn std::error::Error>> {
        let mut builder = tar::Builder::new(Vec::new());
        let mut header = tar::Header::new_gnu();
        header.set_size(body.len() as u64);
        header.set_mode(0o644);
        header.set_cksum();
        builder.append_data(&mut header, name, body)?;
        Ok(builder.into_inner()?)
    }

    struct InsecureEnvGuard {
        _lock: std::sync::MutexGuard<'static, ()>,
        original_insecure: Option<std::ffi::OsString>,
    }

    impl InsecureEnvGuard {
        fn new(insecure: bool) -> Self {
            // Shared with util::security tests, which also toggle OIL_INSECURE_NO_VERIFY.
            let lock = crate::test_support::home_env_lock();
            let original_insecure = std::env::var_os("OIL_INSECURE_NO_VERIFY");
            if insecure {
                std::env::set_var("OIL_INSECURE_NO_VERIFY", "1");
            } else {
                std::env::remove_var("OIL_INSECURE_NO_VERIFY");
            }
            Self {
                _lock: lock,
                original_insecure,
            }
        }
    }

    impl Drop for InsecureEnvGuard {
        fn drop(&mut self) {
            match &self.original_insecure {
                Some(val) => std::env::set_var("OIL_INSECURE_NO_VERIFY", val),
                None => std::env::remove_var("OIL_INSECURE_NO_VERIFY"),
            }
        }
    }

    /// Run the secure path over `apk` with only the built-in keys trusted.
    fn extract_secure(
        apk: &[u8],
    ) -> std::result::Result<(Vec<PathBuf>, tempfile::TempDir), OilError> {
        let dir = tempdir().expect("tempdir");
        let apk_path = dir.path().join("pkg.apk");
        std::fs::write(&apk_path, apk).expect("write apk");
        let empty_root = dir.path().join("keys-root");
        let dest = dir.path().join("dest");
        let (files, _) = extract_tracked_with_keys(&apk_path, &dest, &empty_root)?;
        Ok((files, dir))
    }

    fn member_ranges(apk: &[u8]) -> Vec<Range<usize>> {
        split_gzip_members(apk)
            .expect("split")
            .into_iter()
            .map(|m| m.raw)
            .collect()
    }

    #[test]
    fn genuine_alpine_package_verifies_and_extracts() -> TestResult {
        let _guard = InsecureEnvGuard::new(false);
        let (files, dir) = extract_secure(REAL_APK)?;
        let key = dir.path().join("dest/usr/share/apk/keys").join(REAL_KEY);
        assert!(files.contains(&key), "missing {}", key.display());
        // The package ships the very key that signed it; it must match ours.
        assert_eq!(
            std::fs::read_to_string(&key)?,
            find_apk_key_in_root(Path::new("/nonexistent"), REAL_KEY).unwrap()
        );
        Ok(())
    }

    #[test]
    fn tampered_data_member_is_rejected() -> TestResult {
        let _guard = InsecureEnvGuard::new(false);
        // Re-compress the data tar with one payload byte flipped: still a
        // valid gzip member, but no longer the bytes datahash pins.
        let members = split_gzip_members(REAL_APK)?;
        let mut data_tar = members[2].tar.clone();
        let last_nonzero = data_tar.iter().rposition(|b| *b != 0).unwrap();
        data_tar[last_nonzero] ^= 0x01;
        let mut apk = REAL_APK[..members[2].raw.start].to_vec();
        apk.extend(create_gz_stream(&data_tar)?);

        let err = extract_secure(&apk).unwrap_err();
        assert!(
            err.to_string().contains("data verification failed"),
            "{err}"
        );
        Ok(())
    }

    #[test]
    fn tampered_control_member_is_rejected() -> TestResult {
        let _guard = InsecureEnvGuard::new(false);
        // Swap in a control member carrying the data member's real hash: the
        // datahash would pass, so only the signature can catch it.
        let ranges = member_ranges(REAL_APK);
        let data_hash = hex::encode(<sha2::Sha256 as sha2::Digest>::digest(
            &REAL_APK[ranges[2].clone()],
        ));
        let pkginfo = format!("pkgname = evil\ndatahash = {data_hash}\n");
        let mut apk = REAL_APK[ranges[0].clone()].to_vec();
        apk.extend(create_gz_stream(&tar_with(
            ".PKGINFO",
            pkginfo.as_bytes(),
        )?)?);
        apk.extend_from_slice(&REAL_APK[ranges[2].clone()]);

        let err = extract_secure(&apk).unwrap_err();
        assert!(
            err.to_string().contains("signature verification failed"),
            "{err}"
        );
        Ok(())
    }

    #[test]
    fn unknown_signing_key_is_rejected() -> TestResult {
        let _guard = InsecureEnvGuard::new(false);
        let ranges = member_ranges(REAL_APK);
        let members = split_gzip_members(REAL_APK)?;
        let (_, _, sig) = extract_signatures(&members[0].tar).remove(0);
        let mut apk = create_gz_stream(&tar_with(".SIGN.RSA.someone-else.rsa.pub", &sig)?)?;
        apk.extend_from_slice(&REAL_APK[ranges[1].start..]);

        let err = extract_secure(&apk).unwrap_err();
        assert!(
            err.to_string()
                .contains("no public key found for 'someone-else.rsa.pub'"),
            "{err}"
        );
        Ok(())
    }

    #[test]
    fn members_split_on_real_boundaries() -> TestResult {
        // Member boundaries come from the gzip trailers, not a magic-byte scan.
        let ranges = member_ranges(REAL_APK);
        assert_eq!(ranges, vec![0..661, 661..1161, 1161..REAL_APK.len()]);
        let mut fake_magic = create_gz_stream(&[0x1f, 0x8b, 0x1f, 0x8b])?;
        let first = fake_magic.len();
        fake_magic.extend(create_gz_stream(b"control")?);
        fake_magic.extend(create_gz_stream(b"data")?);
        let members = split_gzip_members(&fake_magic)?;
        assert_eq!(members[0].raw, 0..first);
        assert_eq!(members[0].tar, [0x1f, 0x8b, 0x1f, 0x8b]);
        assert_eq!(members[2].tar, b"data");
        Ok(())
    }

    #[test]
    fn split_rejects_expansion_before_full_allocation() -> TestResult {
        let mut combined = create_gz_stream(&vec![b'a'; 2048])?;
        combined.extend(create_gz_stream(b"control")?);
        combined.extend(create_gz_stream(b"data")?);
        let err = split_gzip_members_with_limits(&combined, 1024, 4096)
            .err()
            .expect("expanded stream must be rejected");
        assert!(err
            .to_string()
            .contains("Stream 0 size 1025 exceeds maximum 1024"));
        Ok(())
    }

    #[test]
    fn split_enforces_aggregate_budget() -> TestResult {
        let mut combined = create_gz_stream(&vec![b'a'; 600])?;
        combined.extend(create_gz_stream(&vec![b'b'; 600])?);
        combined.extend(create_gz_stream(b"data")?);
        let err = split_gzip_members_with_limits(&combined, 1024, 1000)
            .err()
            .expect("aggregate expansion must be rejected");
        assert!(err
            .to_string()
            .contains("Total decompressed size 1001 exceeds maximum 1000"));
        Ok(())
    }

    #[test]
    fn key_lookup_uses_exact_filename_and_rejects_paths() -> TestResult {
        let dir = tempdir()?;
        let keys_dir = dir.path().join("etc/apk/keys");
        std::fs::create_dir_all(&keys_dir)?;
        std::fs::write(
            keys_dir.join("tap.rsa.pub"),
            "-----BEGIN PUBLIC KEY-----\ndata",
        )?;
        assert!(find_apk_key_in_root(dir.path(), "tap.rsa.pub").is_some());
        assert!(find_apk_key_in_root(dir.path(), "tap.rsa").is_none());
        assert!(find_apk_key_in_root(dir.path(), "../etc/passwd").is_none());
        assert!(find_apk_key_in_root(dir.path(), "a/b").is_none());
        assert!(find_apk_key_in_root(dir.path(), "").is_none());
        assert!(find_apk_key_in_root(dir.path(), REAL_KEY).is_some());
        Ok(())
    }

    #[test]
    fn test_extract_tracked_missing_file() -> TestResult {
        let dir = tempdir()?;
        let missing_path = dir.path().join("does_not_exist.apk");
        let dest_dir = dir.path().join("dest");
        let result = extract_tracked(&missing_path, &dest_dir);
        assert!(result.is_err());
        Ok(())
    }

    #[test]
    fn test_untar_invalid_tar() -> TestResult {
        let dir = tempdir()?;
        let invalid_tar_data = b"not a valid tar file";
        let result = untar(invalid_tar_data, dir.path());
        assert!(result.is_err());
        Ok(())
    }

    #[test]
    fn test_is_safe_symlink() {
        let dest_dir = Path::new("/tmp/dest");

        let link_target = Path::new("bar");
        let dest = Path::new("/tmp/dest/foo");
        assert!(is_safe_symlink(link_target, dest, dest_dir));

        let link_target = Path::new("/etc/passwd");
        let dest = Path::new("/tmp/dest/foo");
        assert!(!is_safe_symlink(link_target, dest, dest_dir));

        let link_target = Path::new("../../../etc/passwd");
        let dest = Path::new("/tmp/dest/foo");
        assert!(!is_safe_symlink(link_target, dest, dest_dir));

        let link_target = Path::new("../bar/baz");
        let dest = Path::new("/tmp/dest/foo/qux");
        assert!(is_safe_symlink(link_target, dest, dest_dir));

        let link_target = Path::new("../../tmp/dest/bar");
        let dest = Path::new("/tmp/dest/foo/qux");
        assert!(!is_safe_symlink(link_target, dest, dest_dir));

        let link_target = Path::new("../../tmp/dest/bar");
        let dest = Path::new("/tmp/dest/foo");
        assert!(!is_safe_symlink(link_target, dest, dest_dir));
    }

    #[test]
    fn unsigned_package_needs_insecure_mode() -> TestResult {
        let dir = tempdir()?;
        let dest_dir = dir.path().join("dest");
        let apk_path = dir.path().join("unsigned.apk");

        // Stream 1 is gzip but not a tar, so no signature entry can be found.
        let data_tar_data = tar_with("hello.txt", b"hello world")?;
        let mut apk_data = create_gz_stream(b"dummy sig")?;
        apk_data.extend(create_gz_stream(b"dummy control")?);
        apk_data.extend(create_gz_stream(&data_tar_data)?);
        std::fs::write(&apk_path, &apk_data)?;

        {
            // Secure mode: an unsigned package is rejected before anything is written.
            let _guard = InsecureEnvGuard::new(false);
            let err = extract_tracked(&apk_path, &dest_dir).unwrap_err();
            assert!(
                matches!(
                    &err,
                    OilError::Install(msg)
                        if msg == "APK has no signature stream; set OIL_INSECURE_NO_VERIFY=1 to override"
                ),
                "unexpected error: {err:?}"
            );
            assert!(!dest_dir.exists());
        }

        // Insecure mode: extraction proceeds with the data stream.
        let _guard = InsecureEnvGuard::new(true);
        let (files, dirs) = extract_tracked(&apk_path, &dest_dir)?;
        assert_eq!(files, vec![dest_dir.join("hello.txt")]);
        assert!(dirs.is_empty());
        assert_eq!(
            std::fs::read_to_string(dest_dir.join("hello.txt"))?,
            "hello world"
        );
        Ok(())
    }
}

use std::path::{Component, Path, PathBuf};

use crate::error::{OilError, Result};

pub const MAX_DOWNLOAD_BYTES: usize = 512 * 1024 * 1024;

pub fn insecure_mode() -> bool {
    std::env::var_os("OIL_INSECURE_NO_VERIFY").is_some()
}

pub fn verify_sha256(data: &[u8], expected: &str) -> Result<()> {
    use sha2::{Digest, Sha256};
    let actual = format!("{:x}", Sha256::digest(data));
    let expected = expected.trim().to_ascii_lowercase();
    if actual != expected {
        return Err(OilError::ChecksumMismatch { expected, actual });
    }
    Ok(())
}

pub fn validate_download_url(url: &str) -> Result<()> {
    if !url.starts_with("https://") {
        return Err(OilError::Install(format!(
            "refusing insecure download URL: {url}"
        )));
    }
    if std::env::var_os("OIL_ALLOW_ANY_DOWNLOAD_HOST").is_some() {
        return Ok(());
    }
    let host = url
        .split('/')
        .nth(2)
        .ok_or_else(|| OilError::Install(format!("invalid download URL: {url}")))?;
    if host == "dl-cdn.alpinelinux.org"
        || host.ends_with(".alpinelinux.org")
        || host == "github.com"
        || host == "raw.githubusercontent.com"
        || host == "objects.githubusercontent.com"
        || host.ends_with(".githubusercontent.com")
    {
        return Ok(());
    }
    Err(OilError::Install(format!(
        "download host not allowed: {host} (set OIL_ALLOW_ANY_DOWNLOAD_HOST=1 to override)"
    )))
}

pub fn validate_install_dest(dest: &Path) -> Result<PathBuf> {
    let mut normalized = PathBuf::new();
    for component in dest.components() {
        match component {
            Component::Prefix(_) | Component::RootDir => normalized.push(component.as_os_str()),
            Component::CurDir => {}
            Component::ParentDir => {
                return Err(OilError::Install("install path must not contain ..".into()));
            }
            Component::Normal(part) => normalized.push(part),
        }
    }
    let path_str = normalized.to_string_lossy();
    let allowed = ["/usr/local", "/opt"];
    if allowed
        .iter()
        .any(|prefix| path_str == *prefix || path_str.starts_with(&format!("{prefix}/")))
    {
        Ok(normalized)
    } else {
        Err(OilError::Install(format!(
            "install path not allowed: {path_str} (use /usr/local or /opt/...)"
        )))
    }
}

pub fn resolve_install_dest(prefix: Option<&Path>, relative: &Path) -> Result<PathBuf> {
    let relative = validate_install_dest(relative)?;
    let rel = relative.strip_prefix("/").unwrap_or(relative.as_path());
    let dest = if let Some(prefix) = prefix {
        prefix.join(rel)
    } else if let Some(prefix) = std::env::var_os("OIL_SYSTEM_PREFIX").map(PathBuf::from) {
        prefix.join(rel)
    } else {
        relative
    };
    if dest.components().any(|c| matches!(c, Component::ParentDir)) {
        return Err(OilError::Install(
            "resolved install path escapes prefix".into(),
        ));
    }
    Ok(dest)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_alpine_cdn() {
        validate_download_url("https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/busybox.apk")
            .unwrap();
    }

    #[test]
    fn rejects_http() {
        assert!(validate_download_url("http://dl-cdn.alpinelinux.org/x.apk").is_err());
    }

    #[test]
    fn rejects_parent_install_path() {
        assert!(validate_install_dest(Path::new("/usr/local/../etc")).is_err());
    }

    #[test]
    fn allows_usr_local() {
        assert_eq!(
            validate_install_dest(Path::new("/usr/local")).unwrap(),
            PathBuf::from("/usr/local")
        );
    }

    #[test]
    fn resolve_install_dest_with_custom_prefix() {
        assert_eq!(
            resolve_install_dest(Some(Path::new("/custom/prefix")), Path::new("/usr/local/bin")).unwrap(),
            PathBuf::from("/custom/prefix/usr/local/bin")
        );
    }

    #[test]
    fn resolve_install_dest_without_prefix() {
        assert_eq!(
            resolve_install_dest(None, Path::new("/usr/local/bin")).unwrap(),
            PathBuf::from("/usr/local/bin")
        );
    }

    #[test]
    fn resolve_install_dest_invalid_relative() {
        assert!(resolve_install_dest(Some(Path::new("/custom/prefix")), Path::new("/etc/bin")).is_err());
    }
}

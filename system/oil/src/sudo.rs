use std::path::Path;
use std::process::Command;

use crate::error::{OilError, Result};

pub fn is_permission_error(err: &OilError) -> bool {
    match err {
        OilError::Io(io_err) => matches!(io_err.kind(), std::io::ErrorKind::PermissionDenied),
        OilError::Install(msg) => {
            let msg = msg.to_lowercase();
            msg.contains("permission denied") || msg.contains("os error 13")
        }
        _ => false,
    }
}

pub fn is_running_as_root() -> bool {
    #[cfg(unix)]
    {
        nix::unistd::getuid().is_root()
    }
    #[cfg(not(unix))]
    {
        false
    }
}

fn has_sudo_cached() -> bool {
    Command::new("sudo")
        .args(["-n", "true"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn normalize_path(path: &Path) -> std::path::PathBuf {
    dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

pub fn sudo_remove(path: &Path) -> Result<()> {
    let path = normalize_path(path);
    let status = Command::new("sudo")
        .args(["rm", "-rf", "--"])
        .arg(&path)
        .status()
        .map_err(OilError::Io)?;
    if !status.success() {
        return Err(OilError::Install(format!("sudo rm -rf {} failed", path.display())));
    }
    Ok(())
}

pub fn sudo_mkdir(path: &Path) -> Result<()> {
    let path = normalize_path(path);
    let status = Command::new("sudo")
        .args(["mkdir", "-p", "--"])
        .arg(&path)
        .status()
        .map_err(OilError::Io)?;
    if !status.success() {
        return Err(OilError::Install(format!("sudo mkdir -p {} failed", path.display())));
    }
    Ok(())
}

pub fn sudo_symlink(src: &Path, dst: &Path) -> Result<()> {
    let src = normalize_path(src);
    let dst = normalize_path(dst);
    let _ = Command::new("sudo").args(["rm", "-f", "--"]).arg(&dst).status();
    let status = Command::new("sudo")
        .args(["ln", "-sf", "--"])
        .arg(&src)
        .arg(&dst)
        .status()
        .map_err(OilError::Io)?;
    if !status.success() {
        return Err(OilError::Install(format!("sudo ln -sf {} {} failed", src.display(), dst.display())));
    }
    Ok(())
}

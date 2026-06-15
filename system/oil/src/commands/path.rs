use crate::error::Result;
use std::path::PathBuf;

/// Print the shell command to add oil's bin directory to PATH.
/// Run: eval "$(oil path)"
pub fn oil_path() -> Result<()> {
    let bins = oil_bin_dirs();
    let path_entries: Vec<String> = bins.iter().map(|b| b.to_string_lossy().to_string()).collect();
    println!("export PATH=\"{path}:$PATH\"", path = path_entries.join(":"));
    Ok(())
}

/// Determine oil's bin directories (where binaries are linked after install).
pub fn oil_bin_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    // System install prefix (e.g. ~/.local/bin or /usr/local/bin)
    dirs.push(crate::system::installer::SystemInstaller::install_prefix().join("bin"));
    // Homebrew-style Cellar bin (e.g. ~/.local/oil/bin)
    if let Ok(prefix) = crate::install::InstallMode::detect().prefix() {
        let cellar_bin = prefix.join("bin");
        if cellar_bin != dirs[0] {
            dirs.push(cellar_bin);
        }
    } else {
        let bp = crate::bottle::homebrew_prefix().join("bin");
        if bp != dirs[0] {
            dirs.push(bp);
        }
    }
    dirs
}

/// Primary bin dir (for system installer wrapper symlinks).
pub fn oil_bin_dir() -> PathBuf {
    oil_bin_dirs().into_iter().next().unwrap_or_else(|| PathBuf::from("/usr/local/bin"))
}

/// Find the git binary: check oil prefix first, then system PATH.
fn find_git() -> PathBuf {
    // Check oil prefix bin dirs first (git installed via oil)
    for dir in oil_bin_dirs() {
        let candidate = dir.join("git");
        if candidate.exists() {
            return candidate;
        }
    }
    // Also check usr/bin under the prefix (APK-style installs)
    if let Some(root) = oil_bin_dir().parent() {
        let candidate = root.join("usr/bin/git");
        if candidate.exists() {
            return candidate;
        }
    }
    PathBuf::from("git")
}

/// Create a git Command configured with GIT_EXEC_PATH if stock git lacks remote-https.
/// Works under doas/sudo by checking the original user's oil prefix.
pub fn git_cmd() -> tokio::process::Command {
    let git_path = find_git();
    let mut cmd = tokio::process::Command::new(&git_path);
    let has_https = std::process::Command::new(&git_path)
        .args(["--exec-path"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| PathBuf::from(s.trim()))
        .map(|p| p.join("git-remote-https").exists())
        .unwrap_or(false);
    if !has_https {
        let oil_root = oil_bin_dir().parent().map(|p| p.to_path_buf());
        let mut found = false;
        if let Some(ref root) = oil_root {
            for candidate in ["usr/libexec/git-core", "usr/lib/git-core", "libexec/git-core"] {
                if root.join(candidate).join("git-remote-https").exists() {
                    cmd.env("GIT_EXEC_PATH", root.join(candidate));
                    found = true;
                    break;
                }
            }
        }
        if !found && nix::unistd::getuid().is_root() {
            if let Ok(logname_out) = std::process::Command::new("logname").output() {
                let user = String::from_utf8_lossy(&logname_out.stdout).trim().to_string();
                if !user.is_empty() && user != "root" {
                    let home = PathBuf::from("/home").join(&user).join(".local");
                    for candidate in ["usr/libexec/git-core", "usr/lib/git-core", "libexec/git-core"] {
                        if home.join(candidate).join("git-remote-https").exists() {
                            cmd.env("GIT_EXEC_PATH", home.join(candidate));
                            break;
                        }
                    }
                }
            }
        }
    }
    cmd
}

/// If running as root, link oil itself into /usr/local/bin so it's in PATH.
pub fn ensure_self_linked() {
    use std::path::Path;
    if !nix::unistd::getuid().is_root() {
        return;
    }
    let target = Path::new("/usr/local/bin/oil");
    if target.exists() {
        return;
    }
    let self_exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(_) => return,
    };
    if let Some(parent) = target.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::remove_file(target);
    #[cfg(unix)]
    let _ = std::os::unix::fs::symlink(&self_exe, target);
}

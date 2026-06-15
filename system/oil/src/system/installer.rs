use crate::bottle::BottleDownloader;
use crate::error::{Result, OilError};
use crate::system::extractor::extract_package_tracked;
use crate::system::manifest::FileManifest;
use crate::system::registry::PackageMetadata;
use crate::system::scripts::run_post_install_script;
use crate::ui::{ProgressBarGuard, PROGRESS_BAR_CHARS, PROGRESS_BAR_TEMPLATE};
use indicatif::{MultiProgress, ProgressBar, ProgressStyle};
use sha2::Digest;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tempfile::TempDir;
use tokio::sync::Semaphore;
use tracing::debug;

type PackageManifestData = (usize, String, String, PathBuf, Vec<PathBuf>, Vec<PathBuf>);
type PackageDownloadData = (usize, String, String, PathBuf);

pub struct SystemInstaller {
    downloader: Arc<BottleDownloader>,
}

impl SystemInstaller {
    pub fn new() -> Self {
        Self {
            downloader: Arc::new(BottleDownloader::new()),
        }
    }

    /// Download and install a set of packages (already dependency-resolved).
    /// Uses parallel downloads like the bottle installer.
    /// Returns (name, version) pairs for successfully installed packages.
    pub async fn install_packages(
        &self,
        packages: &[PackageMetadata],
        prefix: &Path,
        run_scripts: bool,
    ) -> Result<Vec<(String, String)>> {
        if packages.is_empty() {
            return Ok(vec![]);
        }

        std::fs::create_dir_all(prefix)?;

        let mp = MultiProgress::new();
        let semaphore = Arc::new(Semaphore::new(BottleDownloader::GLOBAL_CONNECTION_POOL));

        // Probe sizes first so we can allocate connections proportionally
        let sizes: Vec<u64> = {
            let mut futs = Vec::new();
            for pkg in packages {
                let dl = Arc::clone(&self.downloader);
                let url = pkg.download_url.clone();
                futs.push(async move { dl.probe_size(&url).await });
            }
            futures::future::join_all(futs).await
        };

        let total_size: u64 = sizes.iter().sum();
        let pool = BottleDownloader::GLOBAL_CONNECTION_POOL;

        let tmp_dir = TempDir::new()?;
        let mut tasks = Vec::new();

        for (index, (pkg, &size)) in packages.iter().zip(sizes.iter()).enumerate() {
            let max_conns = if total_size == 0 {
                1
            } else {
                ((size as f64 / total_size as f64) * pool as f64)
                    .round()
                    .max(1.0) as usize
            };

            let pkg_name = pkg.name.clone();
            let pkg_version = pkg.version.clone();
            let url = pkg.download_url.clone();
            let sha256 = pkg.sha256.clone();

            // Derive filename from URL
            let filename = url
                .split('/')
                .next_back()
                .unwrap_or("package.bin")
                .to_string();
            let dest = tmp_dir.path().join(&filename);

            let pb = mp.add(ProgressBar::new(size.max(1)));
            pb.set_style(
                ProgressStyle::default_bar()
                    .template(PROGRESS_BAR_TEMPLATE)
                    .unwrap()
                    .progress_chars(PROGRESS_BAR_CHARS),
            );
            pb.set_message(format!("{} {}", pkg_name, pkg_version));

            let dl = Arc::clone(&self.downloader);
            let sem = Arc::clone(&semaphore);
            let pb_clone = pb.clone();

            tasks.push(tokio::spawn(async move {
                let _permit = sem
                    .acquire_many(max_conns as u32)
                    .await
                    .map_err(|e| OilError::InstallError(format!("Semaphore error: {}", e)))?;

                debug!("Downloading {} from {}", pkg_name, url);
                let mut clear_guard = ProgressBarGuard::new(&pb_clone);
                dl.download(&url, &dest, Some(&pb_clone), max_conns, None)
                    .await?;
                clear_guard.clear_now();

                // Verify SHA256 if available
                if let Some(ref expected) = sha256 {
                    let mut file = std::fs::File::open(&dest)?;
                    let mut hasher = sha2::Sha256::new();
                    let mut buf = [0u8; 8192];
                    loop {
                        let n = file.read(&mut buf)?;
                        if n == 0 {
                            break;
                        }
                        hasher.update(&buf[..n]);
                    }
                    let actual = hex::encode(hasher.finalize());
                    if actual != *expected {
                        return Err(OilError::ChecksumMismatch {
                            expected: expected.clone(),
                            actual,
                        });
                    }
                }

                Ok::<PackageDownloadData, OilError>((index, pkg_name, pkg_version, dest))
            }));
        }

        let mut installed = Vec::new();
        let mut downloads: Vec<PackageDownloadData> = Vec::new();
        let mut manifest_data: Vec<PackageManifestData> = Vec::new();

        let mut failures = Vec::new();
        for task in tasks {
            match task.await {
                Ok(Ok((index, name, version, package_path))) => {
                    downloads.push((index, name.clone(), version.clone(), package_path));
                    installed.push((name, version));
                }
                Ok(Err(e)) => failures.push(e.to_string()),
                Err(e) => failures.push(format!("package task failed to join: {}", e)),
            }
        }

        if !failures.is_empty() {
            return Err(OilError::InstallError(format!(
                "failed to install {} of {} packages:\n{}",
                failures.len(),
                packages.len(),
                failures
                    .into_iter()
                    .map(|failure| format!("  - {failure}"))
                    .collect::<Vec<_>>()
                    .join("\n")
            )));
        }

        downloads.sort_by_key(|(index, _, _, _)| *index);
        for (index, name, version, package_path) in downloads {
            let (files, dirs) = extract_package_tracked(&package_path, prefix)?;
            debug!("Extracted {} to {:?}", name, prefix);
            manifest_data.push((index, name, version, package_path, files, dirs));
        }

        manifest_data.sort_by_key(|(index, _, _, _, _, _)| *index);
        let all_files: Vec<PathBuf> = manifest_data
            .iter()
            .flat_map(|(_, _, _, _, files, _)| files.iter().cloned())
            .collect();
        for (_, _, _, _, files, _) in &mut manifest_data {
            wrap_prefix_commands(prefix, files, &all_files)?;
        }
        link_wrappers_to_bin(prefix, &all_files)?;

        if run_scripts {
            for (_, name, _, package_path, _, _) in &manifest_data {
                run_post_install_script(package_path, prefix).map_err(|e| {
                    OilError::InstallError(format!(
                        "post-install script for {} failed: {}",
                        name, e
                    ))
                })?;
            }
        }

        // Save manifests for each successfully installed package. A missing
        // manifest would make oil think the install never happened, so surface
        // this as an install failure rather than silently losing state.
        for (_, name, version, _, files, dirs) in manifest_data {
            let manifest = FileManifest {
                package: name,
                version,
                files,
                dirs,
                installed_at: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs() as i64,
            };
            manifest.save().await.map_err(|e| {
                OilError::InstallError(format!(
                    "failed to save file manifest for {}: {}",
                    manifest.package, e
                ))
            })?;
        }

        if installed.len() != packages.len() {
            return Err(OilError::InstallError(format!(
                "installed {} of {} resolved packages",
                installed.len(),
                packages.len()
            )));
        }

        Ok(installed)
    }

    /// Determine the install prefix based on whether we have root.
    pub fn install_prefix() -> std::path::PathBuf {
        if let Ok(prefix) = std::env::var("WAX_SYSTEM_PREFIX") {
            if !prefix.trim().is_empty() {
                return std::path::PathBuf::from(prefix);
            }
        }

        // ponytail: when root (doas/sudo), use /usr/local so binaries land in PATH
        if nix::unistd::getuid().is_root() {
            return std::path::PathBuf::from("/usr/local");
        }

        if let Ok(home) = std::env::var("HOME") {
            return std::path::PathBuf::from(home).join(".local");
        }

        crate::ui::dirs::oil_dir()
            .unwrap_or_else(|_| std::path::PathBuf::from("/tmp"))
            .join("system")
            .join("root")
    }
}

fn wrap_prefix_commands(
    prefix: &Path,
    files: &mut Vec<PathBuf>,
    library_files: &[PathBuf],
) -> Result<()> {
    if prefix == Path::new("/") {
        return Ok(());
    }

    let executable_dirs = [
        PathBuf::from("bin"),
        PathBuf::from("sbin"),
        PathBuf::from("usr/bin"),
        PathBuf::from("usr/sbin"),
    ];
    let library_dirs = prefix_library_dirs(prefix, library_files);
    if library_dirs.is_empty() {
        return Ok(());
    }
    let ld_library_path = library_dirs
        .iter()
        .map(|path| shell_quote(&path.to_string_lossy()))
        .collect::<Vec<_>>()
        .join(":");
    let real_root = prefix.join(".oil-real");

    let mut additions = Vec::new();
    for file in files.iter() {
        if std::fs::symlink_metadata(file)?.file_type().is_symlink() {
            continue;
        }
        let Ok(relative) = file.strip_prefix(prefix) else {
            continue;
        };
        let Some(parent) = relative.parent() else {
            continue;
        };
        if !executable_dirs.iter().any(|dir| dir == parent) || !is_elf(file)? {
            continue;
        }

        let real_path = real_root.join(relative);
        let Some(real_dir) = real_path.parent() else {
            continue;
        };
        std::fs::create_dir_all(real_dir)?;
        if real_path.exists() {
            std::fs::remove_file(&real_path)?;
        }
        std::fs::rename(file, &real_path)?;

        let script = format!(
            "#!/bin/sh\nif [ -n \"${{LD_LIBRARY_PATH:-}}\" ]; then\n  export LD_LIBRARY_PATH={}:\"$LD_LIBRARY_PATH\"\nelse\n  export LD_LIBRARY_PATH={}\nfi\nexec {} \"$@\"\n",
            ld_library_path,
            ld_library_path,
            shell_quote(&real_path.to_string_lossy())
        );
        let mut wrapper = std::fs::File::create(file)?;
        wrapper.write_all(script.as_bytes())?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = wrapper.metadata()?.permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(file, perms)?;
        }

        additions.push(real_path);
    }

    files.extend(additions);
    Ok(())
}

/// Symlink wrapper scripts from subdirectories (usr/bin, sbin, usr/sbin) up to bin/
/// so they're on the user's PATH without needing every subdirectory.
fn link_wrappers_to_bin(prefix: &Path, files: &[PathBuf]) -> Result<()> {
    let bin_dir = prefix.join("bin");
    let subdirs = ["usr/bin", "sbin", "usr/sbin"];

    for file in files {
        let Ok(relative) = file.strip_prefix(prefix) else {
            continue;
        };
        let Some(parent) = relative.parent() else {
            continue;
        };
        let parent_str = parent.to_string_lossy();
        if !subdirs.contains(&parent_str.as_ref()) {
            continue;
        }
        let Some(name) = file.file_name() else {
            continue;
        };
        let link = bin_dir.join(name);
        if link.exists() {
            continue;
        }
        std::fs::create_dir_all(&bin_dir)?;
        #[cfg(unix)]
        let _ = std::os::unix::fs::symlink(file, &link);
    }
    Ok(())
}

fn prefix_library_dirs(prefix: &Path, files: &[PathBuf]) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    for file in files {
        let Some(parent) = file.parent() else {
            continue;
        };
        let Ok(relative_parent) = parent.strip_prefix(prefix) else {
            continue;
        };
        if !relative_parent
            .components()
            .any(|component| component.as_os_str() == "lib" || component.as_os_str() == "lib64")
        {
            continue;
        }
        let Some(name) = file.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if !name.contains(".so") {
            continue;
        }
        if !dirs.iter().any(|dir| dir == parent) {
            dirs.push(parent.to_path_buf());
        }
    }
    dirs
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn is_elf(path: &Path) -> Result<bool> {
    let mut file = std::fs::File::open(path)?;
    let mut magic = [0u8; 4];
    match file.read_exact(&mut magic) {
        Ok(()) => Ok(magic == [0x7f, b'E', b'L', b'F']),
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => Ok(false),
        Err(e) => Err(e.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::OnceLock;
    use tempfile::TempDir;
    use tokio::sync::Mutex;

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    #[tokio::test]
    async fn install_prefix_defaults_to_home_local() {
        let _guard = env_lock().lock().await;
        let tmp = TempDir::new().unwrap();
        std::env::set_var("HOME", tmp.path());
        std::env::remove_var("WAX_SYSTEM_PREFIX");

        assert_eq!(SystemInstaller::install_prefix(), tmp.path().join(".local"));
    }

    #[tokio::test]
    async fn install_prefix_uses_explicit_system_prefix() {
        let _guard = env_lock().lock().await;
        let tmp = TempDir::new().unwrap();
        let prefix = tmp.path().join("system-root");
        std::env::set_var("HOME", tmp.path());
        std::env::set_var("WAX_SYSTEM_PREFIX", &prefix);

        assert_eq!(SystemInstaller::install_prefix(), prefix);
        std::env::remove_var("WAX_SYSTEM_PREFIX");
    }

    #[test]
    fn wrapper_handles_multiple_command_and_library_dirs() {
        let tmp = TempDir::new().unwrap();
        let prefix = tmp.path().join("prefix with space");
        let command = prefix.join("bin/tool");
        let library = prefix.join("usr/lib/x86_64-linux-gnu/libthing.so.1");
        std::fs::create_dir_all(command.parent().unwrap()).unwrap();
        std::fs::create_dir_all(library.parent().unwrap()).unwrap();
        std::fs::write(&command, b"\x7fELFpayload").unwrap();
        std::fs::write(&library, b"library").unwrap();
        let mut files = vec![command.clone(), library.clone()];

        let library_files = files.clone();
        wrap_prefix_commands(&prefix, &mut files, &library_files).unwrap();

        let real = prefix.join(".oil-real/bin/tool");
        assert!(real.exists());
        assert!(files.contains(&real));
        let wrapper = std::fs::read_to_string(&command).unwrap();
        assert!(wrapper.contains("'"));
        assert!(wrapper.contains("usr/lib/x86_64-linux-gnu"));
        assert!(wrapper.contains(".oil-real/bin/tool"));
    }

    #[test]
    fn wrapper_skips_root_prefix() {
        let mut files = vec![PathBuf::from("/usr/bin/tool")];
        let library_files = files.clone();
        wrap_prefix_commands(Path::new("/"), &mut files, &library_files).unwrap();
        assert_eq!(files, vec![PathBuf::from("/usr/bin/tool")]);
    }

    #[cfg(unix)]
    #[test]
    fn wrapper_skips_symlinked_commands() {
        let tmp = TempDir::new().unwrap();
        let prefix = tmp.path().join("prefix");
        let command = prefix.join("usr/bin/tool");
        let target = prefix.join("usr/lib/tool-real");
        let library = prefix.join("usr/lib/libthing.so.1");
        std::fs::create_dir_all(command.parent().unwrap()).unwrap();
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(&target, b"\x7fELFpayload").unwrap();
        std::fs::write(&library, b"library").unwrap();
        std::os::unix::fs::symlink("../lib/tool-real", &command).unwrap();
        let mut files = vec![command.clone(), target, library];

        let library_files = files.clone();
        wrap_prefix_commands(&prefix, &mut files, &library_files).unwrap();

        assert!(std::fs::symlink_metadata(&command)
            .unwrap()
            .file_type()
            .is_symlink());
        assert!(!prefix.join(".oil-real/usr/bin/tool").exists());
    }
}

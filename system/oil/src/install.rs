use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::error::Result;

/// Where `oil install` puts packages. Images bind /state/oil here, so
/// packages and the database below survive reboots and share /state snapshots.
pub const PACKAGE_ROOT: &str = "/opt/oil";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InstalledPackage {
    pub name: String,
    pub version: String,
    pub install_date: i64,
    pub pinned: bool,
    /// Files written by the last install, relative to the package root.
    #[serde(default)]
    pub files: Vec<String>,
}

/// The package root, honouring OIL_SYSTEM_PREFIX for staged roots.
pub fn package_root() -> Result<PathBuf> {
    crate::util::security::resolve_install_dest(None, Path::new(PACKAGE_ROOT))
}

fn state_path() -> Result<PathBuf> {
    Ok(package_root()?.join("var/lib/oil/installed.json"))
}

/// Pre-/opt/oil location, read once so existing records are not lost.
fn legacy_state_path() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|d| d.join(".oil").join("installed.json"))
}

pub struct InstallState {
    packages: HashMap<String, InstalledPackage>,
}

impl InstallState {
    pub fn new() -> Result<Self> {
        let mut path = state_path()?;
        if !path.exists() {
            if let Some(legacy) = legacy_state_path().filter(|p| p.exists()) {
                path = legacy;
            }
        }
        let packages = if path.exists() {
            let raw = std::fs::read_to_string(&path)?;
            serde_json::from_str(&raw).map_err(|e| {
                crate::error::OilError::Install(format!(
                    "corrupt install state {}: {e}",
                    path.display()
                ))
            })?
        } else {
            HashMap::new()
        };
        Ok(Self { packages })
    }

    pub fn load(&self) -> Result<HashMap<String, InstalledPackage>> {
        Ok(self.packages.clone())
    }

    pub fn save(&self) -> Result<()> {
        let path = state_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(&self.packages)?)?;
        Ok(())
    }

    pub fn mark_installed(&mut self, name: &str, version: Option<&str>) {
        let version_str = version.unwrap_or_default();
        let install_date = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        if let Some(pkg) = self.packages.get_mut(name) {
            pkg.version.clear();
            pkg.version.push_str(version_str);
            pkg.install_date = install_date;
        } else {
            let pkg = InstalledPackage {
                name: name.to_string(),
                version: version_str.to_string(),
                install_date,
                pinned: false,
                files: Vec::new(),
            };
            self.packages.insert(name.to_string(), pkg);
        }
    }

    /// Record the files an install wrote (absolute paths under `root`).
    pub fn set_files(&mut self, name: &str, root: &Path, files: &[PathBuf]) {
        if let Some(pkg) = self.packages.get_mut(name) {
            pkg.files = files
                .iter()
                .filter_map(|f| f.strip_prefix(root).ok())
                .map(|f| f.to_string_lossy().into_owned())
                .collect();
        }
    }

    /// Installed packages with at least one recorded file missing from `root`,
    /// e.g. after /state was restored or a transaction was interrupted.
    pub fn broken_packages(&self, root: &Path) -> Vec<String> {
        let mut broken: Vec<String> = self
            .packages
            .values()
            .filter(|pkg| {
                pkg.files
                    .iter()
                    .any(|f| std::fs::symlink_metadata(root.join(f)).is_err())
            })
            .map(|pkg| pkg.name.clone())
            .collect();
        broken.sort();
        broken
    }

    pub fn remove(&mut self, name: &str) -> Result<()> {
        self.packages.remove(name);
        Ok(())
    }

    pub fn clear(&mut self) {
        self.packages.clear();
    }

    pub fn get(&self, name: &str) -> Option<&InstalledPackage> {
        self.packages.get(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::home_env_lock;

    struct EnvGuard {
        _lock: std::sync::MutexGuard<'static, ()>,
        original_home: Option<std::ffi::OsString>,
        original_prefix: Option<std::ffi::OsString>,
    }

    impl EnvGuard {
        fn new() -> Self {
            let lock = home_env_lock();
            let original_home = std::env::var_os("HOME");
            let original_prefix = std::env::var_os("OIL_SYSTEM_PREFIX");
            Self {
                _lock: lock,
                original_home,
                original_prefix,
            }
        }

        /// Point both HOME and the package root prefix at `dir`.
        fn isolate(&self, dir: &Path) {
            std::env::set_var("HOME", dir);
            std::env::set_var("OIL_SYSTEM_PREFIX", dir);
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            for (key, value) in [
                ("HOME", &self.original_home),
                ("OIL_SYSTEM_PREFIX", &self.original_prefix),
            ] {
                match value {
                    Some(v) => std::env::set_var(key, v),
                    None => std::env::remove_var(key),
                }
            }
        }
    }

    #[test]
    fn state_lives_under_the_package_root() -> Result<()> {
        // The database must sit next to the files it describes, under the
        // root that images bind from /state, not in RAM-backed $HOME.
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());
        std::env::set_var("HOME", temp_dir.path().join("ram-home"));

        assert_eq!(package_root()?, temp_dir.path().join("opt/oil"));
        let mut state = InstallState::new()?;
        state.mark_installed("pkg", Some("1.0"));
        state.save()?;
        assert!(temp_dir
            .path()
            .join("opt/oil/var/lib/oil/installed.json")
            .exists());
        assert!(!temp_dir.path().join("ram-home/.oil").exists());
        Ok(())
    }

    #[test]
    fn legacy_home_state_is_still_read() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());
        let legacy = temp_dir.path().join(".oil");
        std::fs::create_dir_all(&legacy)?;
        std::fs::write(
            legacy.join("installed.json"),
            r#"{"old":{"name":"old","version":"1","install_date":0,"pinned":false}}"#,
        )?;

        let state = InstallState::new()?;
        assert_eq!(state.get("old").map(|p| p.version.as_str()), Some("1"));
        assert!(state.get("old").unwrap().files.is_empty());
        Ok(())
    }

    #[test]
    fn broken_packages_lists_only_packages_with_missing_files() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());
        let root = temp_dir.path().join("root");
        std::fs::create_dir_all(root.join("usr/bin"))?;
        std::fs::write(root.join("usr/bin/ok"), "")?;
        std::os::unix::fs::symlink("ok", root.join("usr/bin/ok-link"))?;
        std::os::unix::fs::symlink("gone", root.join("usr/bin/dangling"))?;

        let mut state = InstallState::new()?;
        for name in ["intact", "half", "untracked", "linked"] {
            state.mark_installed(name, Some("1"));
        }
        state.set_files("intact", &root, &[root.join("usr/bin/ok")]);
        state.set_files(
            "half",
            &root,
            &[root.join("usr/bin/ok"), root.join("usr/bin/missing")],
        );
        // A dangling symlink is still the file the package installed.
        state.set_files(
            "linked",
            &root,
            &[root.join("usr/bin/ok-link"), root.join("usr/bin/dangling")],
        );
        assert_eq!(state.broken_packages(&root), vec!["half".to_string()]);
        Ok(())
    }

    #[test]
    fn test_install_state_new() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());

        let state = InstallState::new().expect("Failed to create new InstallState");
        assert!(
            state.packages.is_empty(),
            "New state should have empty packages"
        );
        Ok(())
    }

    #[test]
    fn test_install_state_rejects_corrupt_json() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());
        let oil_dir = temp_dir.path().join("opt/oil/var/lib/oil");
        std::fs::create_dir_all(&oil_dir).expect("create .oil");
        std::fs::write(oil_dir.join("installed.json"), "{not-json").expect("write corrupt state");

        match InstallState::new() {
            Err(crate::error::OilError::Install(msg)) => {
                assert!(
                    msg.contains("corrupt install state"),
                    "unexpected error: {msg}"
                );
            }
            Ok(_) => panic!("corrupt state must not load as empty"),
            Err(other) => panic!("Expected OilError::Install, got {other:?}"),
        }
        Ok(())
    }

    #[test]
    fn test_install_state_save_load() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());

        let mut state = InstallState::new().expect("Failed to create new InstallState");
        state.mark_installed("pkg-a", Some("1.0.0"));
        state.mark_installed("pkg-b", None);
        state.save().expect("Failed to save state");

        let loaded_state = InstallState::new().expect("Failed to load InstallState");

        let pkg_a = loaded_state.get("pkg-a").expect("pkg-a should exist");
        assert_eq!(pkg_a.name, "pkg-a");
        assert_eq!(pkg_a.version, "1.0.0");

        let pkg_b = loaded_state.get("pkg-b").expect("pkg-b should exist");
        assert_eq!(pkg_b.name, "pkg-b");
        assert_eq!(pkg_b.version, "");
        Ok(())
    }

    #[test]
    fn test_install_state_operations() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());

        let mut state = InstallState::new().expect("Failed to create new InstallState");

        state.mark_installed("pkg-c", Some("2.0.0"));
        let pkg = state.get("pkg-c").expect("pkg-c should exist");
        assert_eq!(pkg.name, "pkg-c");
        assert_eq!(pkg.version, "2.0.0");

        state.mark_installed("pkg-c", Some("2.1.0"));
        let pkg = state
            .get("pkg-c")
            .expect("pkg-c should exist and be updated");
        assert_eq!(pkg.version, "2.1.0");

        state.remove("pkg-c").expect("Failed to remove pkg-c");
        assert!(state.get("pkg-c").is_none(), "pkg-c should be removed");

        state.mark_installed("pkg-d", Some("3.0.0"));
        state.clear();
        assert!(
            state.packages.is_empty(),
            "State should be empty after clear"
        );

        Ok(())
    }

    #[test]
    fn test_install_state_load_method() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());

        let mut state = InstallState::new().expect("Failed to create new InstallState");

        // Before adding anything
        let loaded = state.load().expect("Failed to load");
        assert!(loaded.is_empty());

        // Add some packages
        state.mark_installed("pkg-x", Some("1.0.0"));
        state.mark_installed("pkg-y", Some("2.0.0"));

        let loaded = state.load().expect("Failed to load");
        assert_eq!(loaded.len(), 2);

        let pkg_x = loaded
            .get("pkg-x")
            .expect("pkg-x should exist in loaded map");
        assert_eq!(pkg_x.name, "pkg-x");
        assert_eq!(pkg_x.version, "1.0.0");

        let pkg_y = loaded
            .get("pkg-y")
            .expect("pkg-y should exist in loaded map");
        assert_eq!(pkg_y.name, "pkg-y");
        assert_eq!(pkg_y.version, "2.0.0");
        assert!(!pkg_y.pinned);

        assert_eq!(loaded, state.packages);

        Ok(())
    }

    #[test]
    fn test_install_state_clear() -> Result<()> {
        let guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        guard.isolate(temp_dir.path());

        let mut state = InstallState::new().expect("Failed to create new InstallState");

        state.mark_installed("pkg-1", Some("1.0.0"));
        state.mark_installed("pkg-2", Some("2.0.0"));

        assert_eq!(state.packages.len(), 2);

        state.clear();

        assert!(state.packages.is_empty(), "State should be empty after clear");

        Ok(())
    }
}

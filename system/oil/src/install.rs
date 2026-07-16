use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

use crate::error::Result;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InstalledPackage {
    pub name: String,
    pub version: String,
    pub install_date: i64,
    pub pinned: bool,
}

fn state_path() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|d| d.join(".oil").join("installed.json"))
        .ok_or_else(|| crate::error::OilError::Install("$HOME not set".into()))
}

pub struct InstallState {
    packages: HashMap<String, InstalledPackage>,
}

impl InstallState {
    pub fn new() -> Result<Self> {
        let path = state_path()?;
        let packages = if path.exists() {
            let raw = std::fs::read_to_string(&path)?;
            serde_json::from_str(&raw).unwrap_or_default()
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
            };
            self.packages.insert(name.to_string(), pkg);
        }
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
    use std::sync::{Mutex, OnceLock};

    static ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    fn env_lock() -> &'static Mutex<()> {
        ENV_LOCK.get_or_init(|| Mutex::new(()))
    }

    struct EnvGuard {
        _lock: std::sync::MutexGuard<'static, ()>,
        original_home: Option<std::ffi::OsString>,
    }

    impl EnvGuard {
        fn new() -> Self {
            let lock = env_lock().lock().expect("Failed to acquire ENV_LOCK");
            let original_home = std::env::var_os("HOME");
            Self {
                _lock: lock,
                original_home,
            }
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            match &self.original_home {
                Some(home) => std::env::set_var("HOME", home),
                None => std::env::remove_var("HOME"),
            }
        }
    }

    #[test]
    fn test_state_path_no_home() -> Result<()> {
        let _guard = EnvGuard::new();
        std::env::remove_var("HOME");

        let result = state_path();
        assert!(result.is_err(), "Expected error when HOME is not set");
        match result {
            Err(crate::error::OilError::Install(msg)) => {
                assert_eq!(msg, "$HOME not set");
            }
            _ => panic!("Expected OilError::Install"),
        }
        Ok(())
    }

    #[test]
    fn test_state_path_with_home() -> Result<()> {
        let _guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        std::env::set_var("HOME", temp_dir.path());

        let result = state_path().expect("Expected valid state path");
        assert_eq!(result, temp_dir.path().join(".oil").join("installed.json"));
        Ok(())
    }

    #[test]
    fn test_install_state_new() -> Result<()> {
        let _guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        std::env::set_var("HOME", temp_dir.path());

        let state = InstallState::new().expect("Failed to create new InstallState");
        assert!(
            state.packages.is_empty(),
            "New state should have empty packages"
        );
        Ok(())
    }

    #[test]
    fn test_install_state_save_load() -> Result<()> {
        let _guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        std::env::set_var("HOME", temp_dir.path());

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
        let _guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        std::env::set_var("HOME", temp_dir.path());

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
        let _guard = EnvGuard::new();
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        std::env::set_var("HOME", temp_dir.path());

        let mut state = InstallState::new().expect("Failed to create new InstallState");

        // Before adding anything
        let loaded = state.load().expect("Failed to load");
        assert!(loaded.is_empty());

        // Add some packages
        state.mark_installed("pkg-x", Some("1.0.0"));
        state.mark_installed("pkg-y", Some("2.0.0"));

        let loaded = state.load().expect("Failed to load");
        assert_eq!(loaded.len(), 2);

        let pkg_x = loaded.get("pkg-x").expect("pkg-x should exist in loaded map");
        assert_eq!(pkg_x.name, "pkg-x");
        assert_eq!(pkg_x.version, "1.0.0");

        let pkg_y = loaded.get("pkg-y").expect("pkg-y should exist in loaded map");
        assert_eq!(pkg_y.name, "pkg-y");
        assert_eq!(pkg_y.version, "2.0.0");
        assert!(!pkg_y.pinned);

        assert_eq!(loaded, state.packages);

        Ok(())
    }
}

#[cfg(test)]
use std::sync::{Mutex, OnceLock};

#[cfg(test)]
static HOME_ENV_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

#[cfg(test)]
pub fn home_env_lock() -> std::sync::MutexGuard<'static, ()> {
    HOME_ENV_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(|e| e.into_inner())
}

#[cfg(test)]
pub struct IsolatedHome {
    _lock: std::sync::MutexGuard<'static, ()>,
    _dir: tempfile::TempDir,
    previous: Option<std::ffi::OsString>,
}

#[cfg(test)]
impl IsolatedHome {
    pub fn new() -> Self {
        let lock = home_env_lock();
        let dir = tempfile::tempdir().expect("tempdir");
        let previous = std::env::var_os("HOME");
        std::env::set_var("HOME", dir.path());
        Self {
            _lock: lock,
            _dir: dir,
            previous,
        }
    }
}

#[cfg(test)]
impl Drop for IsolatedHome {
    fn drop(&mut self) {
        match &self.previous {
            Some(home) => std::env::set_var("HOME", home),
            None => std::env::remove_var("HOME"),
        }
    }
}

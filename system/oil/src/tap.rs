use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::Read;
use std::path::PathBuf;

use crate::error::{OilError, Result};
use crate::system::registry::PackageMetadata;

use crate::util::cache::{cache_key, is_cache_fresh};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tap {
    pub name: String,
    pub url: String,
}

fn taps_path() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .map(|d| d.join(".oil").join("taps.json"))
        .ok_or_else(|| OilError::Install("$HOME not set".into()))
}

pub struct Taps {
    taps: HashMap<String, Tap>,
}

impl Taps {
    pub fn new() -> Result<Self> {
        let path = taps_path()?;
        let taps = if path.exists() {
            let raw = std::fs::read_to_string(&path)?;
            serde_json::from_str(&raw).unwrap_or_default()
        } else {
            HashMap::new()
        };
        Ok(Self { taps })
    }

    pub fn save(&self) -> Result<()> {
        let path = taps_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, serde_json::to_string_pretty(&self.taps)?)?;
        Ok(())
    }

    pub fn add(&mut self, name: &str, url: &str) {
        self.taps.insert(
            name.to_string(),
            Tap {
                name: name.to_string(),
                url: url.to_string(),
            },
        );
    }

    pub fn remove(&mut self, name: &str) {
        self.taps.remove(name);
    }

    pub fn list(&self) -> Vec<&Tap> {
        let mut taps: Vec<_> = self.taps.values().collect();
        taps.sort_by(|a, b| a.name.cmp(&b.name));
        taps
    }
}

pub fn normalize_tap(name: &str) -> Result<(String, String)> {
    if name.starts_with("http://") {
        return Err(OilError::Install("unencrypted http:// URLs are not allowed".into()));
    }
    if name.starts_with("https://") || name.starts_with("git@") {
        Ok((name.to_string(), name.to_string()))
    } else if name.matches('/').count() == 1 && !name.starts_with('/') && !name.ends_with('/') {
        let trimmed = name.strip_suffix(".git").unwrap_or(name);
        Ok((name.to_string(), format!("https://github.com/{}", trimmed)))
    } else {
        Ok((name.to_string(), name.to_string()))
    }
}

pub struct TapRegistry {
    name: String,
    url: String,
}

impl TapRegistry {
    pub fn new(name: &str, url: &str) -> Self {
        Self {
            name: name.to_string(),
            url: url.to_string(),
        }
    }

    fn index_url(&self) -> String {
        if self.url.starts_with("https://github.com/") {
            let path = self.url.trim_start_matches("https://github.com/");
            format!("https://raw.githubusercontent.com/{}/main/index.json", path)
        } else {
            format!("{}/index.json", self.url.trim_end_matches('/'))
        }
    }

    fn cache_path(&self) -> Result<PathBuf> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| OilError::Install("$HOME not set".into()))?;
        let dir = home.join(".oil").join("cache").join("taps");
        std::fs::create_dir_all(&dir)?;
        Ok(dir.join(format!("tap-{}.json", cache_key(&self.name))))
    }

    pub fn update(&self) -> Result<Vec<PackageMetadata<'static>>> {
        let cache_path = self.cache_path()?;
        let url = self.index_url();

        eprintln!("Fetching tap index: {url}");
        let resp = crate::util::security::get_validated(&url).map_err(|e| {
            OilError::Install(format!("Failed to fetch tap index from {url}: {e}"))
        })?;
        let mut body = Vec::new();
        resp.into_body()
            .into_reader()
            .read_to_end(&mut body)
            .map_err(|e| OilError::Install(format!("Failed to read tap index body: {e}")))?;
        let s = String::from_utf8(body.clone()).unwrap(); let leaked: &'static str = Box::leak(s.into_boxed_str()); let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(leaked)
            .map_err(|e| OilError::Install(format!("Failed to parse tap index: {e}")))?;
        if let Some(parent) = cache_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&cache_path, &body)?;
        Ok(packages)
    }

    pub fn load(&self) -> Result<Vec<PackageMetadata<'static>>> {
        let cache_path = self.cache_path()?;
        if is_cache_fresh(&cache_path) {
            let data = std::fs::read_to_string(&cache_path)?;
            let leaked: &'static str = Box::leak(data.into_boxed_str()); let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(leaked)
                .map_err(|e| OilError::Install(format!("Failed to parse tap index: {e}")))?;
            if packages
                .iter()
                .all(|p| crate::util::security::validate_download_url(&p.download_url).is_ok())
            {
                return Ok(packages);
            }
        }
        self.update()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::borrow::Cow;
    use std::time::{Duration, SystemTime};

    #[test]
    fn normalize_user_repo_shorthand() {
        let (name, url) = normalize_tap("undivisible/tap").unwrap();
        assert_eq!(name, "undivisible/tap");
        assert_eq!(url, "https://github.com/undivisible/tap");
    }

    #[test]
    fn normalize_url_passthrough() {
        let (name, url) = normalize_tap("https://example.com/tap").unwrap();
        assert_eq!(name, "https://example.com/tap");
        assert_eq!(url, "https://example.com/tap");
    }

    #[test]
    fn normalize_git_url_passthrough() {
        let (name, url) = normalize_tap("git@github.com:undivisible/tap.git").unwrap();
        assert_eq!(name, "git@github.com:undivisible/tap.git");
        assert_eq!(url, "git@github.com:undivisible/tap.git");
    }

    #[test]
    fn normalize_user_repo_shorthand_with_git_extension() {
        let (name, url) = normalize_tap("user/repo.git").unwrap();
        assert_eq!(name, "user/repo.git");
        assert_eq!(url, "https://github.com/user/repo");
    }

    #[test]
    fn normalize_http_url_rejected() {
        let err = normalize_tap("http://example.com/tap").unwrap_err();
        assert!(err.to_string().contains("unencrypted"));
    }

    #[test]
    fn normalize_plain_name() {
        let (name, url) = normalize_tap("mytap").unwrap();
        assert_eq!(name, "mytap");
        assert_eq!(url, "mytap");
    }

    #[test]
    fn normalize_too_many_slashes() {
        let (name, url) = normalize_tap("user/repo/extra").unwrap();
        assert_eq!(name, "user/repo/extra");
        assert_eq!(url, "user/repo/extra");
    }

    #[test]
    fn normalize_leading_trailing_slashes() {
        let (name1, url1) = normalize_tap("/leading-slash").unwrap();
        assert_eq!(name1, "/leading-slash");
        assert_eq!(url1, "/leading-slash");

        let (name2, url2) = normalize_tap("trailing-slash/").unwrap();
        assert_eq!(name2, "trailing-slash/");
        assert_eq!(url2, "trailing-slash/");
    }

    #[test]
    fn normalize_empty_string() {
        let (name, url) = normalize_tap("").unwrap();
        assert_eq!(name, "");
        assert_eq!(url, "");
    }

    #[test]
    fn normalize_multiple_git_extensions() {
        let (name, url) = normalize_tap("user/repo.git.git").unwrap();
        assert_eq!(name, "user/repo.git.git");
        assert_eq!(url, "https://github.com/user/repo.git");
    }

    #[test]
    fn normalize_git_in_middle() {
        let (name, url) = normalize_tap("user.git/repo").unwrap();
        assert_eq!(name, "user.git/repo");
        assert_eq!(url, "https://github.com/user.git/repo");
    }

    #[test]
    fn normalize_just_slash() {
        let (name, url) = normalize_tap("/").unwrap();
        assert_eq!(name, "/");
        assert_eq!(url, "/");
    }

    #[test]
    fn index_url_for_github_repo() {
        let registry = TapRegistry::new("undivisible/tap", "https://github.com/undivisible/tap");
        assert_eq!(
            registry.index_url(),
            "https://raw.githubusercontent.com/undivisible/tap/main/index.json"
        );
    }

    #[test]
    fn index_url_for_plain_url() {
        let registry = TapRegistry::new("mytap", "https://example.com/tap");
        assert_eq!(registry.index_url(), "https://example.com/tap/index.json");
    }

    #[test]
    fn test_is_cache_fresh() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("cache.json");

        // 1. Missing file: should return false
        assert!(!is_cache_fresh(&file_path));

        // Create the file
        let file = std::fs::File::create(&file_path).unwrap();

        // 2. Fresh file: should return true
        assert!(is_cache_fresh(&file_path));

        // 3. Stale file: > 24 hours
        let stale_time = SystemTime::now() - Duration::from_secs(25 * 3600);
        let times = std::fs::FileTimes::new().set_modified(stale_time);
        file.set_times(times).unwrap();
        assert!(!is_cache_fresh(&file_path));

        // 4. Future file: modification time in the future
        let future_time = SystemTime::now() + Duration::from_secs(3600);
        let times = std::fs::FileTimes::new().set_modified(future_time);
        file.set_times(times).unwrap();
        assert!(!is_cache_fresh(&file_path));
    }

    struct HomeGuard {
        _lock: std::sync::MutexGuard<'static, ()>,
        previous: Option<std::ffi::OsString>,
    }

    impl HomeGuard {
        fn new() -> Self {
            let lock = crate::test_support::home_env_lock();
            let previous = std::env::var_os("HOME");
            Self {
                _lock: lock,
                previous,
            }
        }

        fn remove_home(self) -> Self {
            std::env::remove_var("HOME");
            self
        }
    }

    impl Drop for HomeGuard {
        fn drop(&mut self) {
            match &self.previous {
                Some(home) => std::env::set_var("HOME", home),
                None => std::env::remove_var("HOME"),
            }
        }
    }

    #[test]
    fn load_refetches_when_cache_has_disallowed_download_url() {
        let _home = crate::test_support::IsolatedHome::new();
        let registry = TapRegistry::new("poison", "https://attacker.example/tap");
        let cache_path = registry.cache_path().expect("cache path");
        let poisoned = [PackageMetadata {
            name: Cow::Owned("evil".into()),
            version: Cow::Owned("1".into()),
            description: Cow::Owned(String::new()),
            download_url: Cow::Owned("https://attacker.example/evil.apk".into()),
            sha256: None,
            installed_size: 0,
            depends: Vec::new(),
            provides: Vec::new(),
        }];
        std::fs::write(
            &cache_path,
            serde_json::to_vec(&poisoned).expect("serialize"),
        )
        .expect("write poisoned tap cache");
        let err = registry
            .load()
            .expect_err("poisoned tap cache must not be used");
        let msg = err.to_string();
        assert!(
            msg.contains("download host not allowed") || msg.contains("Failed to fetch tap index"),
            "unexpected error: {msg}"
        );
    }

    #[test]
    fn test_cache_path_home_not_set() {
        let _guard = HomeGuard::new().remove_home();

        let registry = TapRegistry::new("mytap", "https://example.com/tap");
        let result = registry.cache_path();

        assert!(result.is_err());
        if let Err(e) = result {
            assert_eq!(e.to_string(), "$HOME not set");
        }
    }

    #[test]
    fn test_cache_path_create_dir_error() {
        let _home = crate::test_support::IsolatedHome::new();
        let home_dir = std::path::PathBuf::from(std::env::var_os("HOME").unwrap());

        let cache_dir = home_dir.join(".oil").join("cache").join("taps");
        std::fs::create_dir_all(cache_dir.parent().unwrap()).unwrap();
        std::fs::write(&cache_dir, b"").unwrap();

        let registry = TapRegistry::new("mytap", "https://example.com/tap");
        let result = registry.cache_path();

        assert!(result.is_err());
        if let Err(e) = result {
            assert!(matches!(e, OilError::Io(_)));
        }
    }

    #[test]
    fn load_returns_error_on_corrupt_cache() {
        let _home = crate::test_support::IsolatedHome::new();
        let registry = TapRegistry::new("corrupt", "https://example.com/tap");
        let cache_path = registry.cache_path().expect("cache path");

        std::fs::write(
            &cache_path,
            b"{not valid json}",
        )
        .expect("write corrupt tap cache");

        let err = registry.load().expect_err("corrupt tap cache should return error");
        let msg = err.to_string();
        assert!(msg.contains("Failed to parse tap index"), "unexpected error: {msg}");
    }

    #[test]
    fn load_returns_error_on_missing_cache() {
        let _home = crate::test_support::IsolatedHome::new();
        let registry = TapRegistry::new("missing", "http://invalid.url.that.will.fail");

        let err = registry.load().expect_err("should return error");
        assert!(err.to_string().contains("Failed to fetch tap index"), "unexpected error: {}", err);
    }

    #[test]
    fn load_returns_error_on_invalid_json_structure() {
        let _home = crate::test_support::IsolatedHome::new();
        let registry = TapRegistry::new("invalid_struct", "https://example.com/tap");
        let cache_path = registry.cache_path().expect("cache path");

        std::fs::write(
            &cache_path,
            b"{\"unexpected\": \"format\"}",
        )
        .expect("write invalid json structure to tap cache");

        let err = registry.load().expect_err("invalid json structure in tap cache should return error");
        let msg = err.to_string();
        assert!(msg.contains("invalid type"), "unexpected error: {msg}");
    }

    #[test]
    fn load_returns_error_on_io_error() {
        let _home = crate::test_support::IsolatedHome::new();
        let registry = TapRegistry::new("io_error", "https://example.com/tap");
        let cache_path = registry.cache_path().expect("cache path");

        // Create a directory at the cache path so that reading it as a file fails
        if let Some(parent) = cache_path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::create_dir(&cache_path).expect("create directory at cache path");

        let err = registry.load().expect_err("reading a directory as tap cache should return error");
        assert!(matches!(err, OilError::Io(_)), "unexpected error: {err}");
    }

    #[test]
    fn load_returns_error_on_invalid_utf8_cache() {
        let _home = crate::test_support::IsolatedHome::new();
        let registry = TapRegistry::new("invalid_utf8", "https://example.com/tap");
        let cache_path = registry.cache_path().expect("cache path");

        std::fs::write(
            &cache_path,
            b"\xFF\xFF\xFF",
        )
        .expect("write invalid utf8 tap cache");

        let err = registry.load().expect_err("invalid utf8 tap cache should return error");
        let msg = err.to_string();
        assert!(msg.contains("stream did not contain valid UTF-8") || msg.contains("invalid utf-8"), "unexpected error: {msg}");
    }

    #[test]
    fn load_returns_error_on_invalid_package_data() {
        let _home = crate::test_support::IsolatedHome::new();
        let registry = TapRegistry::new("invalid", "https://example.com/tap");
        let cache_path = registry.cache_path().expect("cache path");

        std::fs::write(
            &cache_path,
            b"[{\"name\":\"foo\"}]",
        )
        .expect("write invalid package data");

        let err = registry.load().expect_err("invalid package data should return error");
        let msg = err.to_string();
        assert!(msg.contains("missing field"), "unexpected error: {msg}");
    }

    #[test]
    fn load_returns_error_when_cache_path_fails() {
        let _guard = HomeGuard::new().remove_home();
        let registry = TapRegistry::new("mytap", "https://example.com/tap");
        let err = registry.load().expect_err("should return error");
        assert_eq!(err.to_string(), "$HOME not set");
    }
}

use std::time::{Duration, SystemTime};
pub fn is_cache_fresh(path: &std::path::Path) -> bool {
    if let Ok(meta) = std::fs::metadata(path) {
        if let Ok(modified) = meta.modified() {
            if let Ok(elapsed) = SystemTime::now().duration_since(modified) {
                return elapsed < Duration::from_secs(24 * 3600);
            }
        }
    }
    false
}
pub fn cache_key(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, SystemTime};
    use tempfile::NamedTempFile;

    #[test]
    fn test_cache_key() {
        assert_eq!(cache_key("hello"), "hello");
        assert_eq!(cache_key("Hello_World"), "Hello-World");
        assert_eq!(cache_key("a1b2_c3!d4"), "a1b2-c3-d4");
        assert_eq!(cache_key("!@#$%^&*()"), "----------");
        assert_eq!(cache_key(""), "");
        assert_eq!(cache_key("../../etc/passwd"), "------etc-passwd");
        assert_eq!(cache_key("foo/bar\\baz"), "foo-bar-baz");
    }

    #[test]
    fn test_is_cache_fresh_not_exists() {
        let path = std::path::Path::new("/path/does/not/exist");
        assert!(!is_cache_fresh(path));
    }

    #[test]
    fn test_is_cache_fresh_new_file() {
        let tmp = NamedTempFile::new().unwrap();
        assert!(is_cache_fresh(tmp.path()));
    }

    #[test]
    fn test_is_cache_fresh_stale_file() {
        let tmp = NamedTempFile::new().unwrap();
        let old_time = SystemTime::now() - Duration::from_secs(25 * 3600);
        tmp.as_file()
            .set_times(std::fs::FileTimes::new().set_modified(old_time))
            .unwrap();
        assert!(!is_cache_fresh(tmp.path()));
    }

    #[test]
    fn test_is_cache_fresh_future_file() {
        let tmp = NamedTempFile::new().unwrap();
        let future_time = SystemTime::now() + Duration::from_secs(3600);
        tmp.as_file()
            .set_times(std::fs::FileTimes::new().set_modified(future_time))
            .unwrap();
        assert!(!is_cache_fresh(tmp.path()));
    }
}

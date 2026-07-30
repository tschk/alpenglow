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
    value.chars().map(|c| if c.is_alphanumeric() { c } else { '-' }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_key() {
        assert_eq!(cache_key("hello"), "hello");
        assert_eq!(cache_key("Hello_World"), "Hello-World");
        assert_eq!(cache_key("a1b2_c3!d4"), "a1b2-c3-d4");
        assert_eq!(cache_key("!@#$%^&*()"), "----------");
        assert_eq!(cache_key(""), "");
    }
}

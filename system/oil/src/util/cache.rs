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

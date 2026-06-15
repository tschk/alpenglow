use crate::error::Result;

#[derive(Debug, Clone)]
pub struct DistroInfo {
    pub name: String,
    pub version: String,
}

impl DistroInfo {
    pub fn detect() -> Result<Option<Self>> {
        let path = "/etc/os-release";
        let Ok(raw) = std::fs::read_to_string(path) else {
            return Ok(None);
        };
        let id = raw.lines().find_map(|line| {
            let value = line.strip_prefix("ID=")?;
            Some(value.trim_matches('"').to_string())
        }).unwrap_or_default();
        let name = raw.lines().find_map(|line| {
            let value = line.strip_prefix("PRETTY_NAME=")?;
            Some(value.trim_matches('"').to_string())
        });
        let version = raw.lines().find_map(|line| {
            let value = line.strip_prefix("VERSION_ID=")?;
            Some(value.trim_matches('"').to_string())
        }).unwrap_or_default();

        if id.is_empty() {
            return Ok(None);
        }
        Ok(Some(DistroInfo {
            name: name.unwrap_or(id),
            version,
        }))
    }
}

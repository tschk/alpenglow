use crate::error::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub fn create_lockfile(packages: &HashMap<String, String>) -> Result<String> {
    Ok(serde_json::to_string_pretty(packages)?)
}

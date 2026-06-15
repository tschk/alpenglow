use crate::error::Result;

pub struct VersionSpec {
    pub name: String,
    pub constraint: Option<String>,
}

pub fn parse_spec(_input: &str) -> Result<VersionSpec> {
    Ok(VersionSpec { name: String::new(), constraint: None })
}

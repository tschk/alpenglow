pub mod apk;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageMetadata {
    pub name: String,
    pub version: String,
    pub description: String,
    pub download_url: String,
    pub sha256: Option<String>,
    pub installed_size: u64,
    pub depends: Vec<String>,
    pub provides: Vec<String>,
}

pub struct PackageIndex {
    pub packages: Vec<PackageMetadata>,
}

impl PackageIndex {
    pub fn find(&self, name: &str) -> Option<&PackageMetadata> {
        self.packages.iter().find(|p| p.name == name).or_else(|| {
            self.packages
                .iter()
                .find(|p| p.provides.iter().any(|prov| prov == name))
        })
    }
}

pub fn parse_dep_name(dep: &str) -> &str {
    let token = dep.split_whitespace().next().unwrap_or(dep);
    token.split(['=', '<', '>']).next().unwrap_or(token).trim()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_dep_name_simple() {
        assert_eq!(parse_dep_name("libc6"), "libc6");
    }

    #[test]
    fn test_parse_dep_name_with_version() {
        assert_eq!(parse_dep_name("libc6 (>= 2.17)"), "libc6");
    }

    #[test]
    fn test_parse_dep_name_with_equals_constraint() {
        assert_eq!(parse_dep_name("rg=14.1.1-r0"), "rg");
    }

    #[test]
    fn test_parse_dep_name_complex_edge_cases() {
        assert_eq!(parse_dep_name(""), "");
        assert_eq!(parse_dep_name("   "), "");
        assert_eq!(parse_dep_name(">=1.0.0"), "");
        assert_eq!(parse_dep_name("pkg=1.0=2.0"), "pkg");
        assert_eq!(parse_dep_name("so:libssl.so.3"), "so:libssl.so.3");
        assert_eq!(parse_dep_name("cmd:bash"), "cmd:bash");
        assert_eq!(parse_dep_name("  pkg  "), "pkg");
    }

    #[test]
    fn test_package_index_find_by_name() {
        let index = PackageIndex {
            packages: vec![
                PackageMetadata {
                    name: "curl".to_string(),
                    version: "8.0.0".to_string(),
                    description: String::new(),
                    download_url: String::new(),
                    sha256: None,
                    installed_size: 0,
                    depends: vec![],
                    provides: vec![],
                },
                PackageMetadata {
                    name: "libssl3".to_string(),
                    version: "3.0.0".to_string(),
                    description: String::new(),
                    download_url: String::new(),
                    sha256: None,
                    installed_size: 0,
                    depends: vec![],
                    provides: vec!["libssl".to_string()],
                },
            ],
        };
        assert!(index.find("curl").is_some());
        assert!(index.find("libssl3").is_some());
        assert!(index.find("libssl").is_some());
        assert!(index.find("nonexistent").is_none());
    }
}

pub mod apk;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageMetadata {
    pub name: String,
    pub version: String,
    pub description: String,
    pub download_url: String,
    pub sha256: Option<String>,
    pub installed_size: u64,
    pub depends: Vec<Arc<str>>,
    pub provides: Vec<Arc<str>>,
}

pub struct PackageIndex {
    pub packages: Vec<PackageMetadata>,
    name_index: HashMap<String, usize>,
    provides_index: HashMap<String, usize>,
}

impl PackageIndex {
    pub fn new(packages: Vec<PackageMetadata>) -> Self {
        let mut name_index = HashMap::new();
        let mut provides_index = HashMap::new();

        for (i, pkg) in packages.iter().enumerate() {
            for prov in &pkg.provides {
                provides_index.entry(prov.to_string()).or_insert(i);
            }
        }

        for (i, pkg) in packages.iter().enumerate() {
            name_index.entry(pkg.name.clone()).or_insert(i);
        }

        Self {
            packages,
            name_index,
            provides_index,
        }
    }

    pub fn find(&self, name: &str) -> Option<&PackageMetadata> {
        if let Some(&i) = self.name_index.get(name) {
            return Some(&self.packages[i]);
        }
        if let Some(&i) = self.provides_index.get(name) {
            return Some(&self.packages[i]);
        }
        None
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
        let index = PackageIndex::new(vec![
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
                provides: vec!["libssl".into()],
            },
        ]);
        assert!(index.find("curl").is_some());
        assert!(index.find("libssl3").is_some());
        assert!(index.find("libssl").is_some());
        assert!(index.find("nonexistent").is_none());
    }
}

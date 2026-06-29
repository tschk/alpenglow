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
    lookup: std::collections::HashMap<String, usize>,
}

impl PackageIndex {
    pub fn new(packages: Vec<PackageMetadata>) -> Self {
        let mut lookup = std::collections::HashMap::with_capacity(packages.len() * 2);
        for (i, p) in packages.iter().enumerate() {
            lookup.entry(p.name.clone()).or_insert(i);
        }
        for (i, p) in packages.iter().enumerate() {
            for prov in &p.provides {
                lookup.entry(prov.clone()).or_insert(i);
            }
        }
        Self { packages, lookup }
    }

    pub fn find(&self, name: &str) -> Option<&PackageMetadata> {
        self.lookup.get(name).map(|&i| &self.packages[i])
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
                provides: vec!["libssl".to_string()],
            },
        ]);
        assert!(index.find("curl").is_some());
        assert!(index.find("libssl3").is_some());
        assert!(index.find("libssl").is_some());
        assert!(index.find("nonexistent").is_none());
    }
}

#[cfg(any(feature = "system-apk", feature = "system-all"))]
pub mod apk;
#[cfg(any(feature = "system-apt", feature = "system-all"))]
pub mod apt;
#[cfg(any(feature = "system-dnf", feature = "system-all"))]
#[cfg(any(feature = "system-dnf", feature = "system-all"))]
pub mod dnf;
#[cfg(any(feature = "system-pacman", feature = "system-all"))]
pub mod pacman;
#[cfg(any(feature = "system-xbps", feature = "system-all"))]
pub mod xbps;
#[cfg(any(feature = "system-nix", feature = "system-all"))]
pub mod nix;

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

/// Strip version constraints from a dep string like "libc6 (>= 2.17)" → "libc6"
pub fn parse_dep_name(dep: &str) -> &str {
    let token = dep
        .split_whitespace()
        .next()
        .unwrap_or(dep)
        .split(['=', '<', '>'])
        .next()
        .unwrap_or(dep)
        .trim();
    token
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
    fn test_parse_dep_name_with_arch() {
        assert_eq!(parse_dep_name("libgcc-s1:amd64"), "libgcc-s1:amd64");
    }

    #[test]
    fn test_parse_dep_name_with_equals_constraint() {
        assert_eq!(parse_dep_name("rg=14.1.1-r0"), "rg");
    }

    #[test]
    fn test_parse_dep_name_with_comparison_constraint() {
        assert_eq!(parse_dep_name("pcre2>=10.43"), "pcre2");
    }

    #[test]
    fn test_package_index_find_by_name() {
        let index = PackageIndex {
            packages: vec![
                PackageMetadata {
                    name: "curl".to_string(),
                    version: "8.0.0".to_string(),
                    description: "".to_string(),
                    download_url: "".to_string(),
                    sha256: None,
                    installed_size: 0,
                    depends: vec![],
                    provides: vec![],
                },
                PackageMetadata {
                    name: "libssl3".to_string(),
                    version: "3.0.0".to_string(),
                    description: "".to_string(),
                    download_url: "".to_string(),
                    sha256: None,
                    installed_size: 0,
                    depends: vec![],
                    provides: vec!["libssl".to_string()],
                },
            ],
        };

        assert!(index.find("curl").is_some());
        assert!(index.find("libssl3").is_some());
        assert!(index.find("libssl").is_some()); // via provides
        assert!(index.find("nonexistent").is_none());
    }
}

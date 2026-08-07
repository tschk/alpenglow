pub mod apk;

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

use crate::error::{OilError, Result};

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
    name_index: HashMap<String, usize>,
    provides_index: HashMap<String, usize>,
}

impl PackageIndex {
    pub fn new(packages: Vec<PackageMetadata>) -> Self {
        let mut name_index = HashMap::new();
        let mut provides_index = HashMap::new();

        for (i, pkg) in packages.iter().enumerate() {
            for prov in &pkg.provides {
                provides_index.entry(prov.clone()).or_insert(i);
            }
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

    /// Resolve `roots` and their transitive dependencies into install order
    /// (dependencies before dependents). Skips names present in `skip`.
    pub fn resolve_install_order<'a>(
        &'a self,
        roots: &[String],
        skip: &HashSet<String>,
    ) -> Result<Vec<&'a PackageMetadata>> {
        let mut order = Vec::new();
        let mut visiting = HashSet::new();
        let mut scheduled = HashSet::new();

        for root in roots {
            self.visit_install_deps(root, skip, &mut visiting, &mut scheduled, &mut order)?;
        }

        Ok(order)
    }

    fn visit_install_deps<'a>(
        &'a self,
        name: &str,
        skip: &HashSet<String>,
        visiting: &mut HashSet<String>,
        scheduled: &mut HashSet<String>,
        order: &mut Vec<&'a PackageMetadata>,
    ) -> Result<()> {
        if skip.contains(name) {
            return Ok(());
        }

        let pkg = self
            .find(name)
            .ok_or_else(|| OilError::FormulaNotFound(name.to_string()))?;

        if scheduled.contains(&pkg.name) {
            return Ok(());
        }

        if visiting.contains(&pkg.name) {
            return Err(OilError::Install(format!(
                "circular dependency involving {}",
                pkg.name
            )));
        }

        visiting.insert(pkg.name.clone());

        for dep in &pkg.depends {
            let dep_name = parse_dep_name(dep);
            if dep_name.is_empty() {
                continue;
            }
            self.visit_install_deps(dep_name, skip, visiting, scheduled, order)?;
        }

        visiting.remove(&pkg.name);
        scheduled.insert(pkg.name.clone());
        order.push(pkg);
        Ok(())
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
    fn test_parse_dep_name() {
        let cases = vec![
            // happy path
            ("libc6", "libc6"),
            // with version and spaces
            ("libc6 (>= 2.17)", "libc6"),
            // with equals constraint
            ("rg=14.1.1-r0", "rg"),
            // with less than constraint
            ("rg<14.1.1-r0", "rg"),
            // with greater than constraint
            ("rg>14.1.1-r0", "rg"),
            // complex edge cases
            ("", ""),
            ("   ", ""),
            (">=1.0.0", ""),
            ("pkg=1.0=2.0", "pkg"),
            ("so:libssl.so.3", "so:libssl.so.3"),
            ("cmd:bash", "cmd:bash"),
            ("  pkg  ", "pkg"),
            // spaces around constraints
            ("pkg = 1.0", "pkg"),
            ("pkg < 1.0", "pkg"),
            ("pkg > 1.0", "pkg"),
            // weird prefixes
            ("!pkg", "!pkg"),
        ];

        for (input, expected) in cases {
            assert_eq!(
                parse_dep_name(input),
                expected,
                "failed on input: '{}'",
                input
            );
        }
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

    #[test]
    fn test_package_index_preserves_first_match_and_input_order() {
        let packages = vec![
            PackageMetadata {
                name: "duplicate".to_string(),
                version: "first".to_string(),
                description: String::new(),
                download_url: String::new(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec!["virtual".to_string(), "shared".to_string()],
            },
            PackageMetadata {
                name: "virtual".to_string(),
                version: "named".to_string(),
                description: String::new(),
                download_url: String::new(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec!["shared".to_string()],
            },
            PackageMetadata {
                name: "duplicate".to_string(),
                version: "second".to_string(),
                description: String::new(),
                download_url: String::new(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec![],
            },
        ];
        let index = PackageIndex::new(packages);

        assert_eq!(
            index
                .packages
                .iter()
                .map(|pkg| pkg.version.as_str())
                .collect::<Vec<_>>(),
            vec!["first", "named", "second"]
        );
        assert_eq!(index.find("duplicate").unwrap().version, "first");
        assert_eq!(index.find("virtual").unwrap().version, "named");
        assert_eq!(index.find("shared").unwrap().version, "first");
        assert!(PackageIndex::new(vec![]).find("").is_none());
    }

    #[test]
    fn test_package_index_find_edge_cases() {
        let empty_index = PackageIndex::new(vec![]);
        assert!(empty_index.find("anything").is_none());
        assert!(empty_index.find("").is_none());

        let index = PackageIndex::new(vec![
            PackageMetadata {
                name: "pkgA".to_string(),
                version: "1.0.0".to_string(),
                description: String::new(),
                download_url: String::new(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec!["providerA".to_string(), "shared".to_string()],
            },
            PackageMetadata {
                name: "providerA".to_string(),
                version: "2.0.0".to_string(),
                description: String::new(),
                download_url: String::new(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec!["shared".to_string()],
            },
        ]);

        assert!(index.find("pkga").is_none());

        let found = index.find("providerA").unwrap();
        assert_eq!(found.version, "2.0.0");

        let found_shared = index.find("shared").unwrap();
        assert_eq!(found_shared.version, "1.0.0");
    }

    fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata {
        PackageMetadata {
            name: name.to_string(),
            version: "1.0.0".to_string(),
            description: String::new(),
            download_url: String::new(),
            sha256: None,
            installed_size: 0,
            depends,
            provides: vec![],
        }
    }

    #[test]
    fn test_resolve_install_order_deps_before_dependents() {
        let index = PackageIndex::new(vec![
            sample_pkg("app", vec!["liba".to_string()]),
            sample_pkg("liba", vec![]),
        ]);
        let skip = HashSet::new();
        let order = index
            .resolve_install_order(&["app".to_string()], &skip)
            .expect("resolve order");
        let names: Vec<&str> = order.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["liba", "app"]);
    }

    #[test]
    fn test_resolve_install_order_transitive() {
        let index = PackageIndex::new(vec![
            sample_pkg("app", vec!["libb".to_string()]),
            sample_pkg("libb", vec!["liba".to_string()]),
            sample_pkg("liba", vec![]),
        ]);
        let skip = HashSet::new();
        let order = index
            .resolve_install_order(&["app".to_string()], &skip)
            .expect("resolve order");
        let names: Vec<&str> = order.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["liba", "libb", "app"]);
    }

    #[test]
    fn test_resolve_install_order_skips_installed() {
        let index = PackageIndex::new(vec![
            sample_pkg("app", vec!["liba".to_string()]),
            sample_pkg("liba", vec![]),
        ]);
        let skip = HashSet::from(["liba".to_string()]);
        let order = index
            .resolve_install_order(&["app".to_string()], &skip)
            .expect("resolve order");
        let names: Vec<&str> = order.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, vec!["app"]);
    }

    #[test]
    fn test_resolve_install_order_circular_dependency() {
        let index = PackageIndex::new(vec![
            sample_pkg("a", vec!["b".to_string()]),
            sample_pkg("b", vec!["a".to_string()]),
        ]);
        let skip = HashSet::new();
        let result = index.resolve_install_order(&["a".to_string()], &skip);
        assert!(result.is_err());
        let err = result.expect_err("circular dep").to_string();
        assert!(err.contains("circular dependency"));
    }
}

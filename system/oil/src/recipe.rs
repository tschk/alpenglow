//! Oil declarative recipe format.
//!
//! Modeled loosely on ypkg's `package.yml` shape (name / version / source /
//! build steps / install path) but scoped to exactly what Oil's existing
//! internal package representation (`system::registry::PackageMetadata`)
//! needs. Oil is APK-only and today only downloads and extracts prebuilt
//! `.apk` files (see `system/apk_extract`), so a recipe's `source.url`
//! points at a `.apk`, not at upstream tarball sources to compile.
//!
//! A recipe deserializes straight into the same `PackageMetadata` type the
//! Alpine APKINDEX loader (`system::registry::apk`) already produces, so
//! `install_package()` in `main.rs` doesn't need a second code path: a
//! recipe is just another `PackageMetadata` source.
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::error::Result;
use crate::system::registry::PackageMetadata;

fn default_install_path() -> String {
    "/usr/local".to_string()
}

/// Where to fetch the package payload from.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct RecipeSource {
    pub url: String,
    #[serde(default)]
    pub sha256: Option<String>,
}

/// A declarative package recipe (`*.yml`).
///
/// `build` is a list of shell command steps. Oil doesn't build from source
/// yet (it only fetches+extracts prebuilt `.apk` payloads), so today this
/// is always empty for a passthrough recipe.
///
/// ponytail: `build` steps are parsed and kept on the struct but never
/// executed. There is no sandboxing/chroot for build steps because nothing
/// runs them yet. If a recipe starts running real (untrusted) build
/// scripts, add sandboxing (e.g. a bwrap/chroot jail with no network past
/// the initial source fetch) before wiring execution in.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct Recipe {
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub description: String,
    pub source: RecipeSource,
    #[serde(default)]
    pub build: Vec<String>,
    #[serde(default = "default_install_path")]
    pub install: String,
    #[serde(default)]
    pub depends: Vec<String>,
    #[serde(default)]
    pub provides: Vec<String>,
}

impl Recipe {
    /// Parse a recipe from a YAML string, validating the fields Oil
    /// actually needs to be non-empty.
    pub fn parse(yaml: &str) -> Result<Self> {
        let recipe: Recipe = serde_norway::from_str(yaml)?;
        recipe.validate()?;
        Ok(recipe)
    }

    /// Load and parse a recipe from a `.yml` file on disk.
    pub fn load(path: &Path) -> Result<Self> {
        let text = std::fs::read_to_string(path)?;
        Self::parse(&text)
    }

    fn validate(&self) -> Result<()> {
        if self.name.trim().is_empty() {
            return Err(crate::error::OilError::Recipe(
                "'name' must not be empty".into(),
            ));
        }
        if self.version.trim().is_empty() {
            return Err(crate::error::OilError::Recipe(
                "'version' must not be empty".into(),
            ));
        }
        if self.source.url.trim().is_empty() {
            return Err(crate::error::OilError::Recipe(
                "'source.url' must not be empty".into(),
            ));
        }
        Ok(())
    }

    /// Convert into Oil's existing install-time package representation.
    /// This is the same type the Alpine APKINDEX loader produces, so
    /// `install_package()` treats a recipe-sourced package identically to
    /// a registry-sourced one.
    pub fn to_package_metadata(&self) -> PackageMetadata {
        PackageMetadata {
            name: self.name.clone(),
            version: self.version.clone(),
            description: self.description.clone(),
            download_url: self.source.url.clone(),
            sha256: self.source.sha256.clone(),
            installed_size: 0,
            depends: self.depends.iter().map(|s| std::sync::Arc::from(s.as_str())).collect(),
            provides: self.provides.iter().map(|s| std::sync::Arc::from(s.as_str())).collect(),
        }
    }

    /// Destination root the package payload should be unpacked under.
    pub fn install_dest(&self) -> PathBuf {
        PathBuf::from(&self.install)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_recipe() {
        let yaml = r#"
name: toybox
version: 0.8.13-r0
source:
  url: https://dl-cdn.alpinelinux.org/alpine/edge/testing/x86_64/toybox-0.8.13-r0.apk
  sha256: c24fc17a556859e3b5fd6a1fdb079c5b60c02872dba1113a37fcfab222b6d73e
"#;
        let recipe = Recipe::parse(yaml).expect("recipe should parse");
        assert_eq!(recipe.name, "toybox");
        assert_eq!(recipe.version, "0.8.13-r0");
        assert!(recipe.build.is_empty());
        assert_eq!(recipe.install, "/usr/local");
        assert_eq!(
            recipe.source.sha256.as_deref(),
            Some("c24fc17a556859e3b5fd6a1fdb079c5b60c02872dba1113a37fcfab222b6d73e")
        );
    }

    #[test]
    fn parses_full_recipe_with_build_steps_and_deps() {
        let yaml = r#"
name: dinit
version: 0.21.0-r0
description: Service monitoring/init system
source:
  url: https://dl-cdn.alpinelinux.org/alpine/edge/community/x86_64/dinit-0.21.0-r0.apk
  sha256: 98bfaf584025c79233f100b594a1c95ea6c5dee5d38b199c610efa7f6070a1f3
build:
  - echo "no build steps for a passthrough APK recipe"
install: /usr/local
depends:
  - so:libc.musl-x86_64.so.1
provides:
  - cmd:dinit
"#;
        let recipe = Recipe::parse(yaml).expect("recipe should parse");
        assert_eq!(recipe.build.len(), 1);
        assert_eq!(recipe.depends, vec!["so:libc.musl-x86_64.so.1".to_string()]);
        assert_eq!(recipe.provides, vec!["cmd:dinit".to_string()]);
        assert_eq!(recipe.install_dest(), PathBuf::from("/usr/local"));

        let meta = recipe.to_package_metadata();
        assert_eq!(meta.name, "dinit");
        assert_eq!(meta.version, "0.21.0-r0");
        assert_eq!(meta.download_url, recipe.source.url);
        assert_eq!(meta.sha256, recipe.source.sha256);
    }

    #[test]
    fn rejects_missing_name() {
        let yaml = r#"
name: ""
version: "1.0"
source:
  url: https://example.com/pkg.apk
"#;
        let err = Recipe::parse(yaml).expect_err("empty name should be rejected");
        assert!(err.to_string().contains("'name'"));
    }

    #[test]
    fn rejects_missing_source_url() {
        let yaml = r#"
name: pkg
version: "1.0"
source:
  url: ""
"#;
        let err = Recipe::parse(yaml).expect_err("empty source url should be rejected");
        assert!(err.to_string().contains("'source.url'"));
    }

    #[test]
    fn rejects_malformed_yaml() {
        let yaml = "name: [unterminated";
        assert!(Recipe::parse(yaml).is_err());
    }

    #[test]
    fn load_reads_recipe_from_disk() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("pkg.yml");
        std::fs::write(
            &path,
            "name: pkg\nversion: \"1.0\"\nsource:\n  url: https://example.com/pkg.apk\n",
        )
        .expect("write recipe");
        let recipe = Recipe::load(&path).expect("recipe should load");
        assert_eq!(recipe.name, "pkg");
    }
}

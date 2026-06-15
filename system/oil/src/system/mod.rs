pub mod distro;
pub mod extractor;
pub mod generations;
pub mod installer;
pub mod manifest;
pub mod query;
pub mod registry;
pub mod resolver;
pub mod scripts;
pub mod state;

use crate::error::{OilError, Result};
use crate::system::distro::DistroInfo;
use crate::system::generations::{Generation, GenerationManager};
use crate::system::installer::SystemInstaller;
use crate::system::manifest::FileManifest;
use crate::system::registry::{PackageIndex, PackageMetadata};
use crate::system::resolver::Resolver;
use crate::system::state::SystemState;
use std::collections::{HashMap, HashSet};
use std::process::Command;

pub struct SystemManager {
    platform_label: String,
    gen_mgr: GenerationManager,
    installer: SystemInstaller,
}

impl SystemManager {
    pub fn detect() -> Result<Option<Self>> {
        if let Some(distro) = DistroInfo::detect()? {
            let gen_mgr = GenerationManager::new()?;
            gen_mgr.ensure_initialized()?;
            let installer = SystemInstaller::new(&distro)?;
            let platform_label = if distro.version.is_empty() {
                distro.name
            } else {
                format!("{} {}", distro.name, distro.version)
            };
            Ok(Some(Self { platform_label, gen_mgr, installer }))
        } else {
            Ok(None)
        }
    }

    pub fn find_available(name: &str) -> Result<Option<PackageMetadata>> {
        let registry = crate::system::registry::apk::ApkRegistry::alpine_default();
        let index = registry.load()?;
        Ok(index.find(name).cloned())
    }

    pub fn search(&self, query: &str, limit: usize) -> Result<()> {
        let registry = crate::system::registry::apk::ApkRegistry::alpine_default();
        let index = registry.load()?;
        let q = query.to_lowercase();
        let mut results: Vec<&PackageMetadata> = index.packages.iter()
            .filter(|p| p.name.to_lowercase().contains(&q) || p.description.to_lowercase().contains(&q))
            .collect();
        results.sort_by(|a, b| a.name.cmp(&b.name));
        results.truncate(limit);
        for pkg in &results {
            println!("{:<20} {}", pkg.name, pkg.version);
        }
        Ok(())
    }

    pub fn status(&self) -> Result<()> {
        let state = SystemState::load()?;
        let count = state.installed.len();
        println!("System packages: {count} installed");
        println!("Platform: {}", self.platform_label);
        Ok(())
    }

    pub fn list_generations(&self) -> Result<Vec<Generation>> {
        self.gen_mgr.list()
    }

    pub fn current_generation(&self) -> Result<Option<Generation>> {
        self.gen_mgr.current()
    }

    pub fn upgrade_all(&self) -> Result<()> {
        let index = crate::system::registry::apk::ApkRegistry::alpine_default();
        let index = index.load()?;
        let state = SystemState::load()?;
        for (name, pkg) in &state.installed {
            if let Some(latest) = index.find(name) {
                if Some(&latest.version) != pkg.version.as_ref() {
                    println!("Upgrading {name}: {} → {}", pkg.version.as_deref().unwrap_or("?"), latest.version);
                }
            }
        }
        Ok(())
    }
}

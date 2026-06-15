/// Wax-managed system package support.
///
/// Wax keeps its own declarative state, package manifests, and generations
/// while resolving packages through native distribution registries. Installed
/// files and wax-owned state remain the source of truth for managed packages.
pub mod distro;
pub mod extractor;
pub mod generations;
pub mod installer;
pub mod manifest;
#[allow(dead_code)]
pub mod query;
pub mod registry;
pub mod resolver;
pub mod scripts;
pub mod state;

use crate::error::{Result, OilError};
use crate::system::distro::DistroInfo;
use crate::system::generations::{Generation, GenerationManager};
use crate::system::installer::SystemInstaller;
use crate::system::manifest::FileManifest;
use crate::system::registry::{PackageIndex, PackageMetadata};
use crate::system::resolver::Resolver;
use crate::system::state::SystemState;
use crate::system_pm::SystemPm;
use console::style;
use std::collections::{HashMap, HashSet};
use std::process::Command;

pub struct SystemManager {
    pm: SystemPm,
    platform_label: String,
    gen_mgr: GenerationManager,
    installer: SystemInstaller,
}

impl SystemManager {
    pub async fn detect() -> Result<Option<Self>> {
        let Some(pm) = SystemPm::detect().await else {
            return Ok(None);
        };

        let platform_label = if cfg!(target_os = "macos") {
            "macOS".to_string()
        } else if let Some(distro) = DistroInfo::detect().await? {
            if distro.version.is_empty() {
                distro.name
            } else {
                format!("{} {}", distro.name, distro.version)
            }
        } else {
            std::env::consts::OS.to_string()
        };

        let gen_mgr = GenerationManager::new().await?;
        Ok(Some(Self {
            pm,
            platform_label,
            gen_mgr,
            installer: SystemInstaller::new(),
        }))
    }

    pub fn distro_label(&self) -> &str {
        &self.platform_label
    }

    pub async fn upgrade_all(&self) -> Result<()> {
        let mut state = SystemState::load().await?;
        self.refresh_tracked_state(&mut state).await?;
        state.save().await?;

        let index = self.load_registry().await?;
        let upgrades = packages_requiring_upgrade(&state.installed_packages(), &index);

        if upgrades.is_empty() {
            println!(
                "{} all Wax-managed system packages are up to date",
                style("✓").green()
            );
            return Ok(());
        }

        println!("upgrading {} Wax-managed system packages:", upgrades.len());
        for package in &upgrades {
            println!("  {} {}", style("↻").cyan(), style(package).magenta());
        }

        self.snapshot(&format!("pre-upgrade {}", upgrades.join(" ")))
            .await?;
        self.remove_managed_packages(&upgrades).await?;
        self.install_native(&upgrades, false, true).await
    }

    pub async fn install_with_options(&self, packages: &[String], run_scripts: bool) -> Result<()> {
        self.install_native(packages, false, run_scripts).await
    }

    pub async fn add_with_options(&self, packages: &[String], run_scripts: bool) -> Result<()> {
        self.install_native(packages, true, run_scripts).await
    }

    pub async fn remove(&self, packages: &[String]) -> Result<()> {
        if packages.is_empty() {
            return Ok(());
        }

        self.snapshot(&format!("pre-remove {}", packages.join(" ")))
            .await?;
        self.remove_managed_packages(packages).await?;

        let mut state = SystemState::load().await?;
        for pkg in packages {
            state.undeclare(pkg);
            state.mark_removed(pkg);
        }
        self.refresh_tracked_state(&mut state).await?;
        state.save().await?;

        let gen = self
            .gen_mgr
            .create(
                &format!("remove {}", packages.join(" ")),
                state.installed_packages(),
            )
            .await?;

        println!(
            "  {} generation {} created",
            style("✓").green(),
            style(gen.id).bold()
        );
        Ok(())
    }

    pub async fn sync_declared(&self) -> Result<()> {
        let mut state = SystemState::load().await?;
        self.refresh_tracked_state(&mut state).await?;
        state.save().await?;

        if state.declared.is_empty() {
            println!("no declared system packages");
            return Ok(());
        }

        let live_set: HashSet<_> = state.installed.keys().map(|s| s.as_str()).collect();
        let declared_set: HashSet<_> = state.declared.iter().map(|s| s.as_str()).collect();

        let to_install: Vec<String> = declared_set
            .difference(&live_set)
            .map(|s| s.to_string())
            .collect();
        let to_remove: Vec<String> = live_set
            .difference(&declared_set)
            .map(|s| s.to_string())
            .collect();

        if to_install.is_empty() && to_remove.is_empty() {
            println!(
                "{} all declared system packages are installed",
                style("✓").green()
            );
            return Ok(());
        }

        if !to_remove.is_empty() {
            println!("removing {} undeclared managed packages:", to_remove.len());
            for pkg in &to_remove {
                println!("  {} {}", style("-").yellow(), style(pkg).magenta());
            }
            self.remove_managed_packages(&to_remove).await?;
            for pkg in &to_remove {
                state.mark_removed(pkg);
            }
            state.save().await?;
        }

        if to_install.is_empty() {
            state.save().await?;
            let gen = self
                .gen_mgr
                .create("sync", state.installed_packages())
                .await?;
            println!(
                "  {} generation {} created",
                style("✓").green(),
                style(gen.id).bold()
            );
            return Ok(());
        }

        println!("installing {} missing declared packages:", to_install.len());
        for pkg in &to_install {
            println!("  {} {}", style("+").green(), style(pkg).magenta());
        }

        self.install_native(&to_install, true, true).await
    }

    pub async fn list_generations(&self) -> Result<Vec<Generation>> {
        self.gen_mgr.list().await
    }

    pub async fn current_generation(&self) -> Result<Option<Generation>> {
        self.gen_mgr.current().await
    }

    pub async fn rollback(&self, id: Option<u32>) -> Result<()> {
        let target_id = match id {
            Some(i) => i,
            None => self.gen_mgr.previous_id().await?.ok_or_else(|| {
                OilError::InstallError("no previous generation to roll back to".into())
            })?,
        };

        let target =
            self.gen_mgr.get(target_id).await?.ok_or_else(|| {
                OilError::InstallError(format!("generation {} not found", target_id))
            })?;

        let mut state = SystemState::load().await?;
        self.refresh_tracked_state(&mut state).await?;

        let current = state.installed_packages();
        let (to_install, to_remove) = GenerationManager::diff_records(&current, &target.packages);

        if to_install.is_empty() && to_remove.is_empty() {
            println!(
                "{} already at generation {}",
                style("✓").green(),
                style(target_id).bold()
            );
            return Ok(());
        }

        println!(
            "{} rolling back to generation {} ({})",
            style("→").cyan(),
            style(target_id).bold(),
            style(&target.reason).dim()
        );

        if !to_remove.is_empty() {
            let names: Vec<String> = to_remove.iter().map(|p| p.name.clone()).collect();
            println!("  removing: {}", names.join(", "));
            self.remove_managed_packages(&names).await?;
            for name in &names {
                state.mark_removed(name);
            }
        }

        if !to_install.is_empty() {
            let names: Vec<String> = to_install.iter().map(|p| p.name.clone()).collect();
            println!("  installing: {}", names.join(", "));
            self.install_native(&names, false, true).await?;
        }

        self.refresh_tracked_state(&mut state).await?;
        state.save().await?;

        let new_gen = self
            .gen_mgr
            .create(
                &format!("rollback to gen-{}", target_id),
                state.installed_packages(),
            )
            .await?;

        println!(
            "{} rolled back — new generation {}",
            style("✓").green(),
            style(new_gen.id).bold()
        );
        Ok(())
    }

    /// Install packages using Wax's native system package backend.
    pub async fn install_native(
        &self,
        packages: &[String],
        declare: bool,
        run_scripts: bool,
    ) -> Result<()> {
        if packages.is_empty() {
            return Ok(());
        }

        let index = self.load_registry().await?;
        let resolver = Resolver::new(&index);
        let resolved =
            resolver.resolve_with_satisfied(packages, |dep| self.host_dependency_satisfied(dep))?;
        let requested_concrete: HashSet<String> = packages
            .iter()
            .filter_map(|pkg| index.find(crate::system::registry::parse_dep_name(pkg)))
            .map(|pkg| pkg.name.clone())
            .collect();

        // ponytail: skip requested packages that are already on the host system
        let already_hosted: HashSet<&str> = packages
            .iter()
            .filter(|pkg| self.host_package_installed(pkg))
            .map(|s| s.as_str())
            .collect();
        if !already_hosted.is_empty() {
            for pkg in &already_hosted {
                println!(
                    "{} {} already installed via {}",
                    style("✓").green(),
                    style(pkg).magenta(),
                    self.pm.name()
                );
            }
            let remaining: Vec<&String> = packages
                .iter()
                .filter(|p| !already_hosted.contains(p.as_str()))
                .collect();
            if remaining.is_empty() {
                return Ok(());
            }
        }

        let resolved: Vec<&PackageMetadata> = resolved
            .into_iter()
            .filter(|pkg| {
                (requested_concrete.contains(&pkg.name)
                    && !already_hosted.contains(pkg.name.as_str()))
                    || !self.host_package_installed(&pkg.name)
            })
            .collect();

        if resolved.is_empty() {
            return Err(OilError::InstallError(format!(
                "no packages found in registry for: {}",
                packages.join(", ")
            )));
        }

        let dep_count = resolved
            .iter()
            .filter(|pkg| !requested_concrete.contains(&pkg.name))
            .count();
        if dep_count > 0 {
            println!(
                "installing {} + {} {}",
                packages.join(", "),
                dep_count,
                if dep_count == 1 {
                    "dependency"
                } else {
                    "dependencies"
                }
            );
        } else {
            println!("installing {}", packages.join(", "));
        }

        self.snapshot(&format!(
            "pre-{} {}",
            if declare { "add" } else { "install" },
            packages.join(" ")
        ))
        .await?;

        let prefix = SystemInstaller::install_prefix();
        let metadata: Vec<PackageMetadata> = resolved.iter().map(|&p| p.clone()).collect();
        let installed = self
            .installer
            .install_packages(&metadata, &prefix, run_scripts)
            .await?;

        let mut state = SystemState::load().await?;
        if declare {
            for pkg in packages {
                state.declare(pkg);
            }
        }
        for (name, version) in &installed {
            state.mark_installed(
                name,
                Some(version.clone()),
                declare || state.is_declared(name),
            );
        }
        self.refresh_tracked_state(&mut state).await?;
        state.save().await?;

        let gen = self
            .gen_mgr
            .create(
                &format!(
                    "{} {}",
                    if declare { "add" } else { "install" },
                    packages.join(" ")
                ),
                state.installed_packages(),
            )
            .await?;

        for (name, version) in &installed {
            println!("+ {}@{}", style(name).magenta(), style(version).dim());
        }
        println!("{} snapshot gen-{}", style("→").cyan(), style(gen.id).dim());

        // ponytail: after install, link oil itself if needed and hint about PATH
        crate::commands::path::ensure_self_linked();
        let bin_dir = crate::commands::path::oil_bin_dir();
        let bin_str = bin_dir.to_string_lossy();
        let path_ok = std::env::var("PATH")
            .map(|p| p.split(':').any(|d| d == bin_str.as_ref()))
            .unwrap_or(false);
        if !path_ok {
            println!(
                "{} add '{}' to your PATH  (or run: eval \"$(oil path)\")",
                style("→").cyan(),
                bin_str
            );
        }

        Ok(())
    }

    fn host_dependency_satisfied(&self, dependency: &str) -> bool {
        let mut cmd = match self.pm {
            SystemPm::Dnf | SystemPm::Yum => {
                let mut cmd = Command::new("rpm");
                cmd.args(["-q", "--whatprovides", dependency]);
                cmd
            }
            _ => return self.host_package_installed(dependency),
        };

        cmd.output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    fn host_package_installed(&self, package: &str) -> bool {
        let mut cmd = match self.pm {
            SystemPm::Apt => {
                let mut cmd = Command::new("dpkg-query");
                cmd.args(["-W", "-f=${Status}", package]);
                cmd
            }
            SystemPm::Dnf | SystemPm::Yum => {
                let mut cmd = Command::new("rpm");
                cmd.args(["-q", package]);
                cmd
            }
            SystemPm::Pacman => {
                let mut cmd = Command::new("pacman");
                cmd.args(["-Q", package]);
                cmd
            }
            SystemPm::Apk => {
                let mut cmd = Command::new("apk");
                cmd.args(["info", "-e", package]);
                cmd
            }
            SystemPm::Xbps => {
                let mut cmd = Command::new("xbps-query");
                cmd.args(["-l", package]);
                cmd
            }
            #[cfg(any(feature = "system-nix", feature = "system-all"))]
            SystemPm::Nix => {
                let mut cmd = Command::new("nix-env");
                cmd.args(["-q", package]);
                cmd
            }
            _ => return false,
        };

        cmd.output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    async fn load_registry(&self) -> Result<PackageIndex> {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(120))
            .build()
            .map_err(|e| OilError::InstallError(format!("HTTP client: {}", e)))?;

        match self.pm {
            #[cfg(any(feature = "system-apt", feature = "system-all"))]
            SystemPm::Apt => {
                let reg = crate::system::registry::apt::AptRegistry::default_for_host();
                reg.load(&client).await
            }
            #[cfg(any(feature = "system-dnf", feature = "system-all"))]
            SystemPm::Dnf | SystemPm::Yum => {
                let reg = crate::system::registry::dnf::DnfRegistry::default_for_host()?;
                reg.load(&client).await
            }
            #[cfg(any(feature = "system-pacman", feature = "system-all"))]
            SystemPm::Pacman => {
                let reg = crate::system::registry::pacman::PacmanRegistry::arch_default();
                reg.load(&client).await
            }
            #[cfg(any(feature = "system-apk", feature = "system-all"))]
            SystemPm::Apk => {
                let reg = crate::system::registry::apk::ApkRegistry::alpine_default();
                reg.load(&client).await
            }
            #[cfg(any(feature = "system-xbps", feature = "system-all"))]
            SystemPm::Xbps => {
                let reg = crate::system::registry::xbps::XbpsRegistry::void_musl_default();
                reg.load(&client).await
            }
            #[cfg(any(feature = "system-nix", feature = "system-all"))]
            SystemPm::Nix => {
                let reg = crate::system::registry::nix::NixRegistry::default();
                reg.load(&client).await
            }
            _ => Err(OilError::PlatformNotSupported(
                "oil system registry install is not supported for this package manager".into(),
            )),
        }
    }

    pub async fn status(&self) -> Result<()> {
        let mut state = SystemState::load().await?;
        self.refresh_tracked_state(&mut state).await?;
        state.save().await?;
        let current = self.gen_mgr.current().await?;

        println!(
            "{} {}",
            style("platform").bold(),
            style(self.distro_label()).cyan()
        );
        println!(
            "{} {}",
            style("pm      ").bold(),
            style(self.pm.name()).cyan()
        );

        if let Some(gen) = &current {
            println!(
                "{} gen-{} ({}, {})",
                style("gen     ").bold(),
                style(gen.id).bold(),
                style(&gen.reason).dim(),
                gen.age_string()
            );
        } else {
            println!("{} none", style("gen     ").bold());
        }

        println!(
            "{} {} declared, {} installed",
            style("pkgs    ").bold(),
            state.declared.len(),
            state.installed.len()
        );

        if !state.declared.is_empty() {
            println!();
            println!("{}:", style("declared").bold());
            let live: HashSet<_> = state.installed.keys().collect();
            for pkg in &state.declared {
                if live.contains(pkg) {
                    println!("  {} {}", style("✓").green(), style(pkg).magenta());
                } else {
                    println!(
                        "  {} {} {}",
                        style("✗").red(),
                        style(pkg).magenta(),
                        style("(not installed)").dim()
                    );
                }
            }
        }

        Ok(())
    }

    pub async fn search(&self, query: &str, limit: usize) -> Result<()> {
        let results = self.search_registry(query, limit).await?;
        if results.is_empty() {
            println!("no system packages found for {}", style(query).magenta());
            return Ok(());
        }

        println!(
            "{} {} results",
            style("→").cyan(),
            style(results.len()).bold()
        );
        for pkg in results {
            println!(
                "{} {} {}",
                style(pkg.name).magenta(),
                style(pkg.version).dim(),
                pkg.description
            );
        }

        Ok(())
    }

    pub async fn search_registry(&self, query: &str, limit: usize) -> Result<Vec<PackageMetadata>> {
        let q = query.to_lowercase();
        let mut results: Vec<_> = self
            .load_registry()
            .await?
            .packages
            .into_iter()
            .filter(|pkg| {
                pkg.name.to_lowercase().contains(&q)
                    || pkg.description.to_lowercase().contains(&q)
                    || pkg.provides.iter().any(|p| p.to_lowercase().contains(&q))
            })
            .collect();

        results.sort_by(|a, b| {
            let a_exact = a.name.eq_ignore_ascii_case(query);
            let b_exact = b.name.eq_ignore_ascii_case(query);
            b_exact
                .cmp(&a_exact)
                .then_with(|| a.name.len().cmp(&b.name.len()))
                .then_with(|| a.name.cmp(&b.name))
        });
        results.truncate(limit);
        Ok(results)
    }

    async fn live_packages(&self) -> Result<Vec<(String, Option<String>)>> {
        let mut packages: Vec<_> = FileManifest::list_all()
            .await?
            .into_iter()
            .map(|manifest| (manifest.package, Some(manifest.version)))
            .collect();
        packages.sort_by(|a, b| a.0.cmp(&b.0));
        packages.dedup_by(|a, b| a.0 == b.0);
        Ok(packages)
    }

    async fn snapshot(&self, reason: &str) -> Result<()> {
        let mut state = SystemState::load().await?;
        self.refresh_tracked_state(&mut state).await?;
        state.save().await?;

        let packages = state.installed_packages();
        if !packages.is_empty() {
            self.gen_mgr.create(reason, packages).await?;
        }
        Ok(())
    }

    async fn refresh_tracked_state(&self, state: &mut SystemState) -> Result<()> {
        let live = self.live_packages().await?;
        let live_map: HashMap<String, Option<String>> = live.into_iter().collect();
        let installed_names: Vec<String> = state.installed.keys().cloned().collect();

        for name in installed_names {
            if let Some(version) = live_map.get(&name) {
                let declared = state.is_declared(&name);
                state.mark_installed(&name, version.clone(), declared);
            } else {
                state.mark_removed(&name);
            }
        }

        for pkg in &state.declared.clone() {
            if let Some(version) = live_map.get(pkg) {
                state.mark_installed(pkg, version.clone(), true);
            }
        }

        Ok(())
    }

    async fn remove_managed_packages(&self, packages: &[String]) -> Result<()> {
        for package in packages {
            let Some(manifest) = FileManifest::load_any_version(package).await? else {
                return Err(OilError::InstallError(format!(
                    "{} is not installed by oil system manager",
                    package
                )));
            };

            for file in manifest.files.iter().rev() {
                if file.exists() || file.symlink_metadata().is_ok() {
                    let _ = tokio::fs::remove_file(file).await;
                }
            }

            let mut dirs = manifest.dirs.clone();
            dirs.sort_by_key(|b| std::cmp::Reverse(b.components().count()));
            for dir in &dirs {
                let _ = tokio::fs::remove_dir(dir).await;
            }

            if let Ok(path) = FileManifest::manifest_path_pub(package, &manifest.version) {
                let _ = tokio::fs::remove_file(path).await;
            }
        }

        Ok(())
    }
}

fn packages_requiring_upgrade(
    installed: &[(String, Option<String>)],
    index: &PackageIndex,
) -> Vec<String> {
    installed
        .iter()
        .filter_map(|(name, current)| {
            let latest = index.find(name)?;
            if current.as_deref() == Some(latest.version.as_str()) {
                None
            } else {
                Some(name.clone())
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn package(name: &str, version: &str) -> PackageMetadata {
        PackageMetadata {
            name: name.to_string(),
            version: version.to_string(),
            description: String::new(),
            download_url: String::new(),
            sha256: None,
            installed_size: 0,
            depends: vec![],
            provides: vec![],
        }
    }

    #[test]
    fn packages_requiring_upgrade_only_returns_changed_versions() {
        let index = PackageIndex {
            packages: vec![package("curl", "8.1.0"), package("ripgrep", "14.1.1")],
        };
        let installed = vec![
            ("curl".to_string(), Some("8.0.0".to_string())),
            ("ripgrep".to_string(), Some("14.1.1".to_string())),
        ];

        assert_eq!(packages_requiring_upgrade(&installed, &index), vec!["curl"]);
    }

    #[test]
    fn packages_requiring_upgrade_treats_missing_version_as_outdated() {
        let index = PackageIndex {
            packages: vec![package("curl", "8.1.0")],
        };
        let installed = vec![("curl".to_string(), None)];

        assert_eq!(packages_requiring_upgrade(&installed, &index), vec!["curl"]);
    }

    #[test]
    fn packages_requiring_upgrade_ignores_packages_missing_from_registry() {
        let index = PackageIndex { packages: vec![] };
        let installed = vec![("local-only".to_string(), Some("1.0.0".to_string()))];

        assert!(packages_requiring_upgrade(&installed, &index).is_empty());
    }
}

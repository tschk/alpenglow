mod error;
mod install;
mod signal;
mod system;
mod ui;
mod version;

use clap::{Parser, Subcommand};
use error::Result;
use std::io::Read;
use std::path::Path;

#[derive(Parser)]
#[command(name = "oil")]
#[command(version = version::OIL_VERSION)]
#[command(about = "Alpenglow native package manager")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    #[arg(short, long, global = true)]
    verbose: bool,

    #[arg(short, long, global = true, help = "Assume yes for all prompts")]
    yes: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// Search for packages
    Search { query: String },
    /// Show package details
    Info { formula: String },
    /// List installed packages
    List {
        query: Option<String>,
        #[arg(long)]
        upgradable: bool,
    },
    /// Install packages
    Install {
        packages: Vec<String>,
        #[arg(long)]
        dry_run: bool,
        #[arg(long, help = "Install to ~/.local/oil (no sudo)")]
        user: bool,
        #[arg(long, help = "Install to system directory (may need sudo)")]
        global: bool,
    },
    /// Uninstall packages
    Uninstall {
        formulae: Vec<String>,
        #[arg(long)]
        all: bool,
    },
    /// Reinstall packages
    Reinstall {
        packages: Vec<String>,
        #[arg(long)]
        all: bool,
    },
    /// Upgrade packages
    Upgrade {
        packages: Vec<String>,
        #[arg(long)]
        dry_run: bool,
    },
    /// List packages with available updates
    Outdated,
    /// Pin a package to its current version
    Pin {
        packages: Vec<String>,
        #[arg(long, help = "List pinned packages")]
        list: bool,
    },
    /// Unpin a package
    Unpin { packages: Vec<String> },
    /// Show packages not required by any other package
    Leaves,
    /// Show packages that depend on a given package
    Uses {
        formula: String,
        #[arg(long, help = "Only show installed dependents")]
        installed: bool,
    },
    /// Show dependencies for a package
    Deps {
        formula: String,
        #[arg(long, help = "Show as tree")]
        tree: bool,
        #[arg(long, help = "Only installed")]
        installed: bool,
    },
    /// Check system for problems
    Audit,
    /// Show oil installation info
    #[command(name = "oil-info")]
    OilInfo,
}

fn main() {
    signal::install_handler();
    let cli = Cli::parse();

    let result: Result<()> = match cli.command {
        Some(cmd) => run_command(cmd),
        None => {
            eprintln!("Usage: oil <command>\nAlpenglow native package manager\nRun `oil --help` for options");
            Ok(())
        }
    };

    if let Err(e) = result {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}

fn run_command(cmd: Commands) -> Result<()> {
    match cmd {
        Commands::Search { query } => {
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            let q = query.to_lowercase();
            let mut results: Vec<_> = index
                .packages
                .iter()
                .filter(|p| {
                    p.name.to_lowercase().contains(&q) || p.description.to_lowercase().contains(&q)
                })
                .collect();
            results.sort_by(|a, b| a.name.cmp(&b.name));
            for pkg in &results {
                println!("{:<20} {}", pkg.name, pkg.version);
            }
            Ok(())
        }
        Commands::Info { formula } => {
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            match index.find(&formula) {
                Some(pkg) => {
                    println!("Name: {}", pkg.name);
                    println!("Version: {}", pkg.version);
                    println!("Description: {}", pkg.description);
                    println!("URL: {}", pkg.download_url);
                    println!("Depends: {}", pkg.depends.join(", "));
                }
                None => return Err(error::OilError::FormulaNotFound(formula)),
            }
            Ok(())
        }
        Commands::List { query, upgradable } => {
            let state = install::InstallState::new()?;
            let packages = state.load()?;
            let mut list: Vec<_> = packages.into_values().collect();
            list.sort_by(|a, b| a.name.cmp(&b.name));
            for pkg in &list {
                if let Some(ref q) = query {
                    if !pkg.name.contains(q) {
                        continue;
                    }
                }
                if upgradable {
                    // Check against index
                    let registry = system::registry::apk::ApkRegistry::alpine_default();
                    let index = registry.load()?;
                    if let Some(latest) = index.find(&pkg.name) {
                        if latest.version != pkg.version {
                            println!("{} {} -> {}", pkg.name, pkg.version, latest.version);
                        }
                    }
                } else {
                    println!("{} {}", pkg.name, pkg.version);
                }
            }
            Ok(())
        }
        Commands::Install {
            packages,
            dry_run,
            user,
            global,
        } => {
            // For Alpenglow, system install is the default
            let _ = (user, global);
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            let mut state = install::InstallState::new()?;
            for name in &packages {
                let pkg = index
                    .find(name)
                    .ok_or_else(|| error::OilError::FormulaNotFound(name.clone()))?;
                if dry_run {
                    println!("Would install {} {}", pkg.name, pkg.version);
                } else {
                    let dest = std::path::PathBuf::from("/usr/local");
                    install_package(pkg, &dest)?;
                    state.mark_installed(&pkg.name, Some(pkg.version.clone()), true);
                    println!("Installed {} {}", pkg.name, pkg.version);
                }
            }
            if !dry_run {
                state.save()?;
            }
            Ok(())
        }
        Commands::Uninstall { formulae, all } => {
            let mut state = install::InstallState::new()?;
            if all {
                state.clear();
            } else {
                for name in &formulae {
                    state.remove(name)?;
                }
            }
            state.save()?;
            Ok(())
        }
        Commands::Reinstall { packages, all } => {
            let mut state = install::InstallState::new()?;
            let names: Vec<String> = if all {
                state.load()?.into_keys().collect()
            } else {
                packages
            };
            for name in &names {
                if let Some(_pkg) = state.get(name) {
                    let registry = system::registry::apk::ApkRegistry::alpine_default();
                    let index = registry.load()?;
                    if let Some(latest) = index.find(&name) {
                        let dest = std::path::PathBuf::from("/usr/local");
                        install_package(latest, &dest)?;
                        state.mark_installed(&name, Some(latest.version.clone()), true);
                        println!("Reinstalled {name} {}", latest.version);
                    }
                }
            }
            state.save()?;
            Ok(())
        }
        Commands::Upgrade { packages, dry_run } => {
            let mut state = install::InstallState::new()?;
            let installed = state.load()?;
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            let targets: Vec<String> = if packages.is_empty() {
                installed.keys().cloned().collect()
            } else {
                packages
            };
            for name in &targets {
                if let Some(current) = installed.get(name) {
                    if current.pinned {
                        continue;
                    }
                    if let Some(latest) = index.find(name) {
                        if &latest.version != &current.version {
                            if dry_run {
                                println!(
                                    "Would upgrade {name}: {} → {}",
                                    &current.version, &latest.version
                                );
                            } else {
                                let dest = std::path::PathBuf::from("/usr/local");
                                install_package(latest, &dest)?;
                                state.mark_installed(name, Some(latest.version.clone()), true);
                                println!(
                                    "Upgraded {name}: {} → {}",
                                    current.version, latest.version
                                );
                            }
                        }
                    }
                }
            }
            state.save()?;
            Ok(())
        }
        Commands::Outdated => {
            let state = install::InstallState::new()?;
            let installed = state.load()?;
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            for (name, pkg) in &installed {
                if let Some(latest) = index.find(name) {
                    if latest.version != pkg.version {
                        println!("{} {} -> {}", name, pkg.version, latest.version);
                    }
                }
            }
            Ok(())
        }
        Commands::Pin { packages, list } => {
            let mut state = install::InstallState::new()?;
            if list {
                for (name, pkg) in state.load()? {
                    if pkg.pinned {
                        println!("{} {}", name, pkg.version);
                    }
                }
            } else {
                for name in &packages {
                    if let Some(pkg) = state.get_mut(name) {
                        pkg.pinned = true;
                    }
                }
                state.save()?;
            }
            Ok(())
        }
        Commands::Unpin { packages } => {
            let mut state = install::InstallState::new()?;
            for name in &packages {
                if let Some(pkg) = state.get_mut(name) {
                    pkg.pinned = false;
                }
            }
            state.save()?;
            Ok(())
        }
        Commands::Leaves => {
            let state = install::InstallState::new()?;
            let packages = state.load()?;
            let installed_names: std::collections::HashSet<_> = packages.keys().cloned().collect();
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            let mut required = std::collections::HashSet::new();
            for pkg in packages.values() {
                if let Some(meta) = index.find(&pkg.name) {
                    required.extend(
                        meta.depends
                            .iter()
                            .filter(|dep| installed_names.contains(*dep))
                            .cloned(),
                    );
                }
            }
            let mut leaves: Vec<_> = installed_names.difference(&required).cloned().collect();
            leaves.sort();
            for name in leaves {
                println!("{name}");
            }
            Ok(())
        }
        Commands::Uses { formula, installed } => {
            let state = install::InstallState::new()?;
            let installed_packages = state.load()?;
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            let mut users: Vec<_> = index
                .packages
                .iter()
                .filter(|pkg| pkg.depends.iter().any(|dep| dep == &formula))
                .filter(|pkg| !installed || installed_packages.contains_key(&pkg.name))
                .map(|pkg| pkg.name.clone())
                .collect();
            users.sort();
            for name in users {
                println!("{name}");
            }
            Ok(())
        }
        Commands::Deps {
            formula,
            tree,
            installed,
        } => {
            let _ = (tree, installed);
            let registry = system::registry::apk::ApkRegistry::alpine_default();
            let index = registry.load()?;
            if let Some(pkg) = index.find(&formula) {
                for dep in &pkg.depends {
                    println!("{dep}");
                }
            }
            Ok(())
        }
        Commands::Audit => {
            let state = install::InstallState::new()?;
            let packages = state.load()?;
            println!("{} packages installed", packages.len());
            Ok(())
        }
        Commands::OilInfo => {
            println!("oil {}", version::OIL_VERSION);
            println!("Prefix: /usr/local");
            println!(
                "Cache: {}",
                ui::dirs::oil_cache_dir().unwrap_or_default().display()
            );
            Ok(())
        }
    }
}

fn install_package(pkg: &system::registry::PackageMetadata, dest: &Path) -> Result<()> {
    let url = &pkg.download_url;
    eprintln!("Downloading {} {}...", pkg.name, pkg.version);

    let resp = ureq::get(url)
        .call()
        .map_err(|e| error::OilError::Install(format!("download failed for {}: {e}", pkg.name)))?;

    let mut data = Vec::new();
    resp.into_body()
        .into_reader()
        .read_to_end(&mut data)
        .map_err(|e| error::OilError::Install(format!("read failed for {}: {e}", pkg.name)))?;

    let tmp = tempfile::NamedTempFile::new()
        .map_err(|e| error::OilError::Install(format!("temp file: {e}")))?;

    std::fs::write(tmp.path(), &data)
        .map_err(|e| error::OilError::Install(format!("write temp: {e}")))?;

    eprintln!("Extracting {}...", pkg.name);
    system::apk_extract::extract_tracked(tmp.path(), dest)?;

    Ok(())
}

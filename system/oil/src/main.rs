mod error;
mod install;
mod signal;
mod system;

use clap::{Parser, Subcommand};
use error::Result;
use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

#[derive(Parser)]
#[command(name = "oil")]
#[command(version = env!("CARGO_PKG_VERSION"))]
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
    /// Install packages
    Install {
        packages: Vec<String>,
        #[arg(long)]
        dry_run: bool,
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
        Commands::Search { query } => run_search(query),
        Commands::Info { formula } => run_info(formula),
        Commands::Install { packages, dry_run } => run_install(packages, dry_run),
        Commands::Uninstall { formulae, all } => run_uninstall(formulae, all),
        Commands::Reinstall { packages, all } => run_reinstall(packages, all),
        Commands::Upgrade { packages, dry_run } => run_upgrade(packages, dry_run),
        Commands::Outdated => run_outdated(),
    }
}

fn run_search(query: String) -> Result<()> {
    let registry = system::registry::apk::ApkRegistry::alpine_default();
    let index = registry.load()?;
    let q = query.to_lowercase();
    let mut results: Vec<_> = index
        .packages
        .iter()
        .filter(|p| p.name.to_lowercase().contains(&q) || p.description.to_lowercase().contains(&q))
        .collect();
    results.sort_by(|a, b| a.name.cmp(&b.name));
    for pkg in &results {
        println!("{:<20} {}", pkg.name, pkg.version);
    }
    Ok(())
}

fn run_info(formula: String) -> Result<()> {
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

fn run_install(packages: Vec<String>, dry_run: bool) -> Result<()> {
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
            state.mark_installed(&pkg.name, Some(pkg.version.as_str()));
            println!("Installed {} {}", pkg.name, pkg.version);
        }
    }
    if !dry_run {
        state.save()?;
    }
    Ok(())
}

fn run_uninstall(formulae: Vec<String>, all: bool) -> Result<()> {
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

fn run_reinstall(packages: Vec<String>, all: bool) -> Result<()> {
    let mut state = install::InstallState::new()?;
    let names: Vec<String> = if all {
        state.load()?.into_keys().collect()
    } else {
        packages
    };
    let registry = system::registry::apk::ApkRegistry::alpine_default();
    let index = registry.load()?;
    for name in &names {
        if let Some(_pkg) = state.get(name) {
            if let Some(latest) = index.find(name) {
                let dest = std::path::PathBuf::from("/usr/local");
                install_package(latest, &dest)?;
                state.mark_installed(name, Some(latest.version.as_str()));
                println!("Reinstalled {name} {}", latest.version);
            }
        }
    }
    state.save()?;
    Ok(())
}

fn run_upgrade(packages: Vec<String>, dry_run: bool) -> Result<()> {
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
                if latest.version != current.version {
                    if dry_run {
                        println!(
                            "Would upgrade {name}: {} → {}",
                            &current.version, &latest.version
                        );
                    } else {
                        let dest = std::path::PathBuf::from("/usr/local");
                        install_package(latest, &dest)?;
                        state.mark_installed(name, Some(latest.version.as_str()));
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

fn run_outdated() -> Result<()> {
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

    std::fs::set_permissions(tmp.path(), std::fs::Permissions::from_mode(0o600))
        .map_err(|e| error::OilError::Install(format!("set permissions: {e}")))?;

    eprintln!("Extracting {}...", pkg.name);

    let result = system::apk_extract::extract_tracked(tmp.path(), dest);

    let _ = std::fs::remove_file(tmp.path());

    result.map(|_| ())
}

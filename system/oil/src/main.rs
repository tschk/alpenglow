mod error;
mod install;
mod recipe;
mod signal;
mod system;
pub mod util;
#[cfg(test)]
mod test_support;
#[cfg(feature = "wax")]
mod tap;

use clap::{Parser, Subcommand};
use error::Result;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use system::registry::PackageIndex;

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

#[derive(Clone, Debug, PartialEq, Subcommand)]
enum Commands {
    /// Search for packages
    #[command(visible_alias = "s")]
    Search { query: String },
    /// Show package details
    #[command(visible_aliases = ["in", "show"])]
    Info { formula: String },
    /// Install packages
    #[command(visible_aliases = ["i", "add"])]
    Install {
        packages: Vec<String>,
        #[arg(long)]
        dry_run: bool,
    },
    /// Install a package from a declarative recipe (.yml) file
    #[command(visible_alias = "recipe")]
    InstallRecipe {
        recipe: PathBuf,
        #[arg(long)]
        dry_run: bool,
    },
    /// Uninstall packages
    #[command(visible_aliases = ["rm", "del"])]
    Uninstall {
        formulae: Vec<String>,
        #[arg(long)]
        all: bool,
    },
    /// Reinstall packages
    #[command(visible_aliases = ["ri", "re"])]
    Reinstall {
        packages: Vec<String>,
        #[arg(long)]
        all: bool,
    },
    /// Upgrade packages
    #[command(visible_alias = "up")]
    Upgrade {
        packages: Vec<String>,
        #[arg(long)]
        dry_run: bool,
    },
    /// List packages with available updates
    #[command(visible_aliases = ["od", "out"])]
    Outdated,
    /// Update the package index
    #[command(visible_aliases = ["u", "refresh"])]
    Update,
    #[cfg(feature = "wax")]
    /// Manage third-party package taps
    Tap {
        tap: Option<String>,
        #[command(subcommand)]
        action: Option<TapAction>,
    },
}

#[cfg(feature = "wax")]
#[derive(Debug, PartialEq, Clone, Subcommand)]
enum TapAction {
    /// Add a tap
    #[command(visible_alias = "a")]
    Add { tap: String },
    /// Remove a tap
    #[command(visible_aliases = ["rm", "del"])]
    Remove { tap: String },
    /// List configured taps
    #[command(visible_aliases = ["ls", "l"])]
    List,
    /// Update all tap indexes (or one tap)
    #[command(visible_aliases = ["u", "up"])]
    Update { tap: Option<String> },
}

fn main() {
    signal::install_handler();
    let cli = Cli::parse();

    let result: Result<()> = match cli.command {
        Some(cmd) => dispatch_command(cmd),
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

fn dispatch_command(cmd: Commands) -> Result<()> {
    match cmd {
        Commands::Search { query } => run_search(query),
        Commands::Info { formula } => run_info(formula),
        Commands::Install { packages, dry_run } => run_install(packages, dry_run),
        Commands::InstallRecipe { recipe, dry_run } => run_install_recipe(recipe, dry_run),
        Commands::Uninstall { formulae, all } => run_uninstall(formulae, all),
        Commands::Reinstall { packages, all } => run_reinstall(packages, all),
        Commands::Upgrade { packages, dry_run } => run_upgrade(packages, dry_run),
        Commands::Outdated => run_outdated(),
        Commands::Update => run_update(),
        #[cfg(feature = "wax")]
        Commands::Tap { tap, action } => run_tap(tap, action),
    }
}

#[allow(dead_code)]
fn run_command(cmd: Commands) -> Result<()> {
    dispatch_command(cmd)
}

#[cfg(feature = "wax")]
fn load_registry() -> Result<PackageIndex> {
    let apk = system::registry::apk::ApkRegistry::alpine_default().load()?;
    let mut all = apk.packages;
    let taps = tap::Taps::new()?;
    for tap in taps.list() {
        let registry = tap::TapRegistry::new(&tap.name, &tap.url);
        match registry.load() {
            Ok(index) => {
                eprintln!("Loaded {} packages from tap {}", index.packages.len(), tap.name);
                all.extend(index.packages);
            }
            Err(e) => eprintln!("warning: failed to load tap {}: {}", tap.name, e),
        }
    }
    Ok(PackageIndex::new(all))
}

#[cfg(not(feature = "wax"))]
fn load_registry() -> Result<PackageIndex> {
    system::registry::apk::ApkRegistry::alpine_default().load()
}

#[cfg(feature = "wax")]
fn refresh_registry() -> Result<PackageIndex> {
    let apk = system::registry::apk::ApkRegistry::alpine_default().refresh()?;
    let mut all = apk.packages;
    let taps = tap::Taps::new()?;
    for tap in taps.list() {
        let registry = tap::TapRegistry::new(&tap.name, &tap.url);
        match registry.update() {
            Ok(index) => {
                eprintln!("Refreshed {} packages from tap {}", index.packages.len(), tap.name);
                all.extend(index.packages);
            }
            Err(e) => eprintln!("warning: failed to refresh tap {}: {}", tap.name, e),
        }
    }
    Ok(PackageIndex::new(all))
}

#[cfg(not(feature = "wax"))]
fn refresh_registry() -> Result<PackageIndex> {
    system::registry::apk::ApkRegistry::alpine_default().refresh()
}

fn run_update() -> Result<()> {
    let index = refresh_registry()?;
    println!("Updated package index: {} packages", index.packages.len());
    Ok(())
}

fn contains_ignore_ascii_case(haystack: &str, needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    if haystack.len() < needle.len() {
        return false;
    }
    haystack
        .as_bytes()
        .windows(needle.len())
        .any(|w| w.eq_ignore_ascii_case(needle))
}

fn oil_secure_tmp_dir() -> Result<PathBuf> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("USERPROFILE").map(PathBuf::from))
        .ok_or_else(|| error::OilError::Install("HOME or USERPROFILE not set".into()))?;
    let tmp_dir = home.join(".oil").join("tmp");
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        std::fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&tmp_dir)
            .map_err(|e| error::OilError::Install(format!("failed to create secure tmp dir: {e}")))?;
    }
    #[cfg(not(unix))]
    {
        std::fs::create_dir_all(&tmp_dir)
            .map_err(|e| error::OilError::Install(format!("failed to create secure tmp dir: {e}")))?;
    }
    Ok(tmp_dir)
}

fn run_search(query: String) -> Result<()> {
    let index = load_registry()?;
    let q = query.to_ascii_lowercase();
    let q_bytes = q.as_bytes();
    let mut results: Vec<_> = index
        .packages
        .iter()
        .filter(|p| {
            contains_ignore_ascii_case(&p.name, q_bytes)
                || contains_ignore_ascii_case(&p.description, q_bytes)
        })
        .collect();
    results.sort_by(|a, b| a.name.cmp(&b.name));
    if results.is_empty() {
        println!("No packages found for '{}'", query);
    } else {
        for pkg in &results {
            println!("{:<20} {}", pkg.name, pkg.version);
        }
    }
    Ok(())
}

fn run_info(formula: String) -> Result<()> {
    let index = load_registry()?;
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
    let mut state = install::InstallState::new()?;
    let mut pending = Vec::new();

    for name in packages {
        if let Some(pkg) = state.get(&name) {
            println!("{} {} already installed", pkg.name, pkg.version);
        } else {
            pending.push(name);
        }
    }

    if pending.is_empty() {
        return Ok(());
    }

    let index = load_registry()?;
    for name in &pending {
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

fn run_install_recipe(recipe_path: PathBuf, dry_run: bool) -> Result<()> {
    let recipe = recipe::Recipe::load(&recipe_path)?;
    let pkg = recipe.to_package_metadata();
    if dry_run {
        println!(
            "Would install {} {} from recipe {}",
            pkg.name,
            pkg.version,
            recipe_path.display()
        );
        return Ok(());
    }
    let dest = recipe.install_dest();
    install_package(&pkg, &dest)?;
    let mut state = install::InstallState::new()?;
    state.mark_installed(&pkg.name, Some(pkg.version.as_str()));
    state.save()?;
    println!(
        "Installed {} {} (recipe: {})",
        pkg.name,
        pkg.version,
        recipe_path.display()
    );
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
    let index = load_registry()?;
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

fn plan_upgrades<'a>(
    targets: Option<&'a [String]>,
    installed: &'a std::collections::HashMap<String, install::InstalledPackage>,
    index: &'a PackageIndex,
) -> Vec<(
        &'a String,
        &'a install::InstalledPackage,
        &'a system::registry::PackageMetadata,
    )> {
    let mut upgrades = Vec::new();

    if let Some(targets) = targets {
        for name in targets {
            if let Some(current) = installed.get(name) {
                if current.pinned {
                    continue;
                }
                if let Some(latest) = index.find(name) {
                    if latest.version != current.version {
                        upgrades.push((name, current, latest));
                    }
                }
            }
        }
    } else {
        for (name, current) in installed {
            if current.pinned {
                continue;
            }
            if let Some(latest) = index.find(name) {
                if latest.version != current.version {
                    upgrades.push((name, current, latest));
                }
            }
        }
    }

    upgrades
}

fn run_upgrade(packages: Vec<String>, dry_run: bool) -> Result<()> {
    let mut state = install::InstallState::new()?;
    let installed = state.load()?;
    if installed.is_empty() {
        println!("No packages installed");
        return Ok(());
    }
    let index = load_registry()?;
    let targets = if packages.is_empty() {
        None
    } else {
        Some(packages)
    };
    let upgrades = plan_upgrades(targets.as_deref(), &installed, &index);

    for (name, current, latest) in &upgrades {
        if dry_run {
            println!(
                "Would upgrade {name}: {} → {}",
                current.version, latest.version
            );
        } else {
            let dest = std::path::PathBuf::from("/usr/local");
            install_package(latest, &dest)?;
            state.mark_installed(name, Some(latest.version.as_str()));
            println!("Upgraded {name}: {} → {}", current.version, latest.version);
        }
    }
    if upgrades.is_empty() {
        println!("All packages are up to date");
    }
    state.save()?;
    Ok(())
}

fn run_outdated() -> Result<()> {
    let state = install::InstallState::new()?;
    let installed = state.load()?;
    if installed.is_empty() {
        println!("No packages installed");
        return Ok(());
    }
    let index = load_registry()?;
    let mut outdated = 0;
    for (name, pkg) in &installed {
        if let Some(latest) = index.find(name) {
            if latest.version != pkg.version {
                outdated += 1;
                println!("{} {} -> {}", name, pkg.version, latest.version);
            }
        }
    }
    if outdated == 0 {
        println!("All packages are up to date");
    }
    Ok(())
}

#[cfg(feature = "wax")]
fn run_tap(tap: Option<String>, action: Option<TapAction>) -> Result<()> {
    let mut taps = tap::Taps::new()?;

    match action {
        Some(TapAction::Add { tap: name }) => {
            let (name, url) = tap::normalize_tap(&name);
            taps.add(&name, &url);
            taps.save()?;
            println!("Tapped {} ({})", name, url);
        }
        Some(TapAction::Remove { tap: name }) => {
            taps.remove(&name);
            taps.save()?;
            println!("Untapped {}", name);
        }
        Some(TapAction::Update { tap }) => {
            if let Some(name) = tap {
                let entry = taps.list().into_iter().find(|t| t.name == name);
                if let Some(entry) = entry {
                    let registry = tap::TapRegistry::new(&entry.name, &entry.url);
                    let index = registry.update()?;
                    println!("Updated {} ({} packages)", name, index.packages.len());
                } else {
                    return Err(error::OilError::Install(format!("tap not found: {}", name)));
                }
            } else {
                for entry in taps.list() {
                    let registry = tap::TapRegistry::new(&entry.name, &entry.url);
                    match registry.update() {
                        Ok(index) => println!("Updated {} ({} packages)", entry.name, index.packages.len()),
                        Err(e) => eprintln!("warning: failed to update tap {}: {}", entry.name, e),
                    }
                }
            }
        }
        Some(TapAction::List) => {
            let list = taps.list();
            if list.is_empty() {
                println!("No taps configured.");
            } else {
                for t in list {
                    println!("{} {}", t.name, t.url);
                }
            }
        }
        None => {
            if let Some(name) = tap {
                let (name, url) = tap::normalize_tap(&name);
                taps.add(&name, &url);
                taps.save()?;
                println!("Tapped {} ({})", name, url);
            } else {
                let list = taps.list();
                if list.is_empty() {
                    println!("No taps configured.");
                } else {
                    for t in list {
                        println!("{} {}", t.name, t.url);
                    }
                }
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

    let tmp_dir = oil_secure_tmp_dir()?;
    let mut tmp = tempfile::Builder::new()
        .tempfile_in(&tmp_dir)
        .map_err(|e| error::OilError::Install(format!("temp file: {e}")))?;

    tmp.write_all(&data)
        .map_err(|e| error::OilError::Install(format!("write temp: {e}")))?;

    eprintln!("Extracting {}...", pkg.name);

    let result = system::apk_extract::extract_tracked(tmp.path(), dest);

    let _ = std::fs::remove_file(tmp.path());

    result.map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::IsolatedHome;

    #[test]
    fn test_contains_ignore_ascii_case() {
        // Happy paths
        assert!(contains_ignore_ascii_case("hello world", b"world"));
        assert!(contains_ignore_ascii_case("HELLO WORLD", b"world"));
        assert!(contains_ignore_ascii_case("hello world", b"WORLD"));
        assert!(contains_ignore_ascii_case("HeLlO wOrLd", b"WoRlD"));

        // Error/not found
        assert!(!contains_ignore_ascii_case("hello world", b"earth"));
        assert!(!contains_ignore_ascii_case("hello", b"hello world"));

        // Edge cases
        assert!(contains_ignore_ascii_case("hello", b"")); // empty needle
        assert!(contains_ignore_ascii_case("", b"")); // empty both
        assert!(!contains_ignore_ascii_case("", b"hello")); // empty haystack
    }

    #[test]
    fn test_run_install_recipe_dry_run_does_not_touch_network() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("pkg.yml");
        std::fs::write(
            &path,
            "name: pkg\nversion: \"1.0\"\nsource:\n  url: https://example.invalid/pkg.apk\n",
        )
        .expect("write recipe");

        // dry_run must succeed without ever attempting the download.
        run_install_recipe(path, true).expect("dry run install_recipe should succeed");
    }

    #[test]
    fn test_run_install_recipe_missing_file() {
        let result = run_install_recipe(PathBuf::from("/nonexistent/recipe.yml"), true);
        assert!(result.is_err());
    }

    #[test]
    fn cli_parses_command_aliases() {
        let _home = IsolatedHome::new();
        let cases: Vec<(&[&str], Commands)> = vec![
            (&["oil", "s", "vim"], Commands::Search { query: "vim".into() }),
            (
                &["oil", "i", "--dry-run", "zlib"],
                Commands::Install {
                    packages: vec!["zlib".into()],
                    dry_run: true,
                },
            ),
            (
                &["oil", "add", "--dry-run", "zlib"],
                Commands::Install {
                    packages: vec!["zlib".into()],
                    dry_run: true,
                },
            ),
            (
                &["oil", "rm", "pkg"],
                Commands::Uninstall {
                    formulae: vec!["pkg".into()],
                    all: false,
                },
            ),
            (
                &["oil", "del", "pkg"],
                Commands::Uninstall {
                    formulae: vec!["pkg".into()],
                    all: false,
                },
            ),
            (
                &["oil", "ri", "pkg"],
                Commands::Reinstall {
                    packages: vec!["pkg".into()],
                    all: false,
                },
            ),
            (
                &["oil", "up"],
                Commands::Upgrade {
                    packages: vec![],
                    dry_run: false,
                },
            ),
            (&["oil", "u"], Commands::Update),
            (&["oil", "od"], Commands::Outdated),
        ];
        for (argv, want) in cases {
            let cli = Cli::try_parse_from(argv).expect("parse alias argv");
            let cmd = cli.command.expect("subcommand");
            assert_eq!(cmd, want, "argv: {argv:?}");

            // Do not execute run_command in tests for commands that require network
            // or modify the filesystem extensively (like tap add, upgrade, update, etc).
            // We just want to test CLI parsing aliases.
            // run_command(cmd).expect("run_command");
        }
    }

    #[cfg(feature = "wax")]
    #[test]
    fn cli_parses_tap_action_aliases() {
        let _home = IsolatedHome::new();
        let cli = Cli::try_parse_from(["oil", "tap", "add", "org/tap"]).expect("parse");
        let cmd = cli.command.expect("subcommand");
        assert_eq!(
            cmd,
            Commands::Tap {
                tap: None,
                action: Some(TapAction::Add {
                    tap: "org/tap".to_string()
                }),
            }
        );
    }
}

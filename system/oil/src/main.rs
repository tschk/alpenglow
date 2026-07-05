mod error;
mod install;
mod recipe;
mod signal;
mod system;
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
    /// Install a package from a declarative recipe (.yml) file
    InstallRecipe {
        recipe: PathBuf,
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
    /// Update the package index
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
    Add { tap: String },
    /// Remove a tap
    Remove { tap: String },
    /// List configured taps
    List,
    /// Update all tap indexes (or one tap)
    Update { tap: Option<String> },
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

trait CommandRunner {
    fn search(&self, query: String) -> Result<()>;
    fn info(&self, formula: String) -> Result<()>;
    fn install(&self, packages: Vec<String>, dry_run: bool) -> Result<()>;
    fn install_recipe(&self, recipe: PathBuf, dry_run: bool) -> Result<()>;
    fn uninstall(&self, formulae: Vec<String>, all: bool) -> Result<()>;
    fn reinstall(&self, packages: Vec<String>, all: bool) -> Result<()>;
    fn upgrade(&self, packages: Vec<String>, dry_run: bool) -> Result<()>;
    fn outdated(&self) -> Result<()>;
    fn update(&self) -> Result<()>;
    #[cfg(feature = "wax")]
    fn tap(&self, tap: Option<String>, action: Option<TapAction>) -> Result<()>;
}

struct DefaultRunner;

impl CommandRunner for DefaultRunner {
    fn search(&self, query: String) -> Result<()> {
        run_search(query)
    }
    fn info(&self, formula: String) -> Result<()> {
        run_info(formula)
    }
    fn install(&self, packages: Vec<String>, dry_run: bool) -> Result<()> {
        run_install(packages, dry_run)
    }
    fn install_recipe(&self, recipe: PathBuf, dry_run: bool) -> Result<()> {
        run_install_recipe(recipe, dry_run)
    }
    fn uninstall(&self, formulae: Vec<String>, all: bool) -> Result<()> {
        run_uninstall(formulae, all)
    }
    fn reinstall(&self, packages: Vec<String>, all: bool) -> Result<()> {
        run_reinstall(packages, all)
    }
    fn upgrade(&self, packages: Vec<String>, dry_run: bool) -> Result<()> {
        run_upgrade(packages, dry_run)
    }
    fn outdated(&self) -> Result<()> {
        run_outdated()
    }
    fn update(&self) -> Result<()> {
        run_update()
    }
    #[cfg(feature = "wax")]
    fn tap(&self, tap: Option<String>, action: Option<TapAction>) -> Result<()> {
        run_tap(tap, action)
    }
}

fn execute_command<R: CommandRunner>(cmd: Commands, runner: &R) -> Result<()> {
    match cmd {
        Commands::Search { query } => runner.search(query),
        Commands::Info { formula } => runner.info(formula),
        Commands::Install { packages, dry_run } => runner.install(packages, dry_run),
        Commands::InstallRecipe { recipe, dry_run } => runner.install_recipe(recipe, dry_run),
        Commands::Uninstall { formulae, all } => runner.uninstall(formulae, all),
        Commands::Reinstall { packages, all } => runner.reinstall(packages, all),
        Commands::Upgrade { packages, dry_run } => runner.upgrade(packages, dry_run),
        Commands::Outdated => runner.outdated(),
        Commands::Update => runner.update(),
        #[cfg(feature = "wax")]
        Commands::Tap { tap, action } => runner.tap(tap, action),
    }
}

fn run_command(cmd: Commands) -> Result<()> {
    let runner = DefaultRunner;
    execute_command(cmd, &runner)
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

fn run_search(query: String) -> Result<()> {
    let index = load_registry()?;
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

fn compute_upgrades<'a>(
    targets: &[String],
    installed: &std::collections::HashMap<String, install::InstalledPackage>,
    index: &'a system::registry::PackageIndex,
) -> Vec<(&'a system::registry::PackageMetadata, String)> {
    let mut upgrades = Vec::new();
    for name in targets {
        if let Some(current) = installed.get(name) {
            if current.pinned {
                continue;
            }
            if let Some(latest) = index.find(name) {
                if latest.version != current.version {
                    upgrades.push((latest, current.version.clone()));
                }
            }
        }
    }
    upgrades
}

fn run_upgrade(packages: Vec<String>, dry_run: bool) -> Result<()> {
    let mut state = install::InstallState::new()?;
    let installed = state.load()?;
    let index = load_registry()?;
    let targets: Vec<String> = if packages.is_empty() {
        installed.keys().cloned().collect()
    } else {
        packages
    };

    let upgrades = compute_upgrades(&targets, &installed, &index);

    for (latest, current_version) in upgrades {
        let name = &latest.name;
        if dry_run {
            println!(
                "Would upgrade {name}: {} → {}",
                current_version, latest.version
            );
        } else {
            let dest = std::path::PathBuf::from("/usr/local");
            install_package(latest, &dest)?;
            state.mark_installed(name, Some(latest.version.as_str()));
            println!(
                "Upgraded {name}: {} → {}",
                current_version, latest.version
            );
        }
    }
    state.save()?;
    Ok(())
}

fn run_outdated() -> Result<()> {
    let state = install::InstallState::new()?;
    let installed = state.load()?;
    let index = load_registry()?;
    for (name, pkg) in &installed {
        if let Some(latest) = index.find(name) {
            if latest.version != pkg.version {
                println!("{} {} -> {}", name, pkg.version, latest.version);
            }
        }
    }
    Ok(())
}

fn get_secure_temp_dir_in(home: std::path::PathBuf) -> Result<std::path::PathBuf> {
    #[cfg(unix)]
    use std::os::unix::fs::DirBuilderExt;

    let tmp_dir = home.join(".oil").join("tmp");

    if !tmp_dir.exists() {
        let mut builder = std::fs::DirBuilder::new();
        builder.recursive(true);

        #[cfg(unix)]
        builder.mode(0o700);

        builder.create(&tmp_dir)
            .map_err(|e| error::OilError::Install(format!("failed to create temp dir: {e}")))?;
    }
    Ok(tmp_dir)
}

fn get_secure_temp_dir() -> Result<std::path::PathBuf> {
    // We try to get HOME first (Unix), then try USERPROFILE (Windows) as a fallback
    let home = std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(std::path::PathBuf::from)
        .ok_or_else(|| error::OilError::Install("$HOME not set".into()))?;

    get_secure_temp_dir_in(home)
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

    let tmp_dir = get_secure_temp_dir()?;
    let mut tmp = tempfile::Builder::new()
        .prefix("oil-download-")
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
    use std::cell::RefCell;

    #[test]
    fn test_get_secure_temp_dir_in_success() -> Result<()> {
        let temp_dir = tempfile::tempdir().expect("Failed to create tempdir");
        let home = temp_dir.path().to_path_buf();

        let result = get_secure_temp_dir_in(home).expect("Expected valid secure temp dir");
        assert_eq!(result, temp_dir.path().join(".oil").join("tmp"));
        assert!(result.exists(), "Secure temp dir should be created");
        Ok(())
    }

    #[derive(Debug, PartialEq, Clone)]
    enum MockCall {
        Search(String),
        Info(String),
        Install(Vec<String>, bool),
        InstallRecipe(PathBuf, bool),
        Uninstall(Vec<String>, bool),
        Reinstall(Vec<String>, bool),
        Upgrade(Vec<String>, bool),
        Outdated,
        Update,
        #[cfg(feature = "wax")]
        Tap(Option<String>, Option<TapAction>),
    }

    struct MockRunner {
        calls: RefCell<Vec<MockCall>>,
    }

    impl MockRunner {
        fn new() -> Self {
            MockRunner {
                calls: RefCell::new(Vec::new()),
            }
        }

        fn get_calls(&self) -> Vec<MockCall> {
            self.calls.borrow().clone()
        }
    }

    impl CommandRunner for MockRunner {
        fn search(&self, query: String) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Search(query));
            Ok(())
        }
        fn info(&self, formula: String) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Info(formula));
            Ok(())
        }
        fn install(&self, packages: Vec<String>, dry_run: bool) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Install(packages, dry_run));
            Ok(())
        }
        fn install_recipe(&self, recipe: PathBuf, dry_run: bool) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::InstallRecipe(recipe, dry_run));
            Ok(())
        }
        fn uninstall(&self, formulae: Vec<String>, all: bool) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Uninstall(formulae, all));
            Ok(())
        }
        fn reinstall(&self, packages: Vec<String>, all: bool) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Reinstall(packages, all));
            Ok(())
        }
        fn upgrade(&self, packages: Vec<String>, dry_run: bool) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Upgrade(packages, dry_run));
            Ok(())
        }
        fn outdated(&self) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Outdated);
            Ok(())
        }
        fn update(&self) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Update);
            Ok(())
        }
        #[cfg(feature = "wax")]
        fn tap(&self, tap: Option<String>, action: Option<TapAction>) -> Result<()> {
            self.calls.borrow_mut().push(MockCall::Tap(tap, action));
            Ok(())
        }
    }

    #[test]
    fn test_execute_command_search() {
        let runner = MockRunner::new();
        let cmd = Commands::Search { query: "foo".to_string() };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(runner.get_calls(), vec![MockCall::Search("foo".to_string())]);
    }

    #[test]
    fn test_execute_command_info() {
        let runner = MockRunner::new();
        let cmd = Commands::Info { formula: "bar".to_string() };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(runner.get_calls(), vec![MockCall::Info("bar".to_string())]);
    }

    #[test]
    fn test_execute_command_install() {
        let runner = MockRunner::new();
        let cmd = Commands::Install {
            packages: vec!["pkg1".to_string(), "pkg2".to_string()],
            dry_run: true,
        };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(
            runner.get_calls(),
            vec![MockCall::Install(vec!["pkg1".to_string(), "pkg2".to_string()], true)]
        );
    }

    #[test]
    fn test_execute_command_install_recipe() {
        let runner = MockRunner::new();
        let cmd = Commands::InstallRecipe {
            recipe: PathBuf::from("recipes/toybox.yml"),
            dry_run: true,
        };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(
            runner.get_calls(),
            vec![MockCall::InstallRecipe(PathBuf::from("recipes/toybox.yml"), true)]
        );
    }

    #[test]
    fn test_execute_command_uninstall() {
        let runner = MockRunner::new();
        let cmd = Commands::Uninstall {
            formulae: vec!["pkg1".to_string()],
            all: false,
        };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(
            runner.get_calls(),
            vec![MockCall::Uninstall(vec!["pkg1".to_string()], false)]
        );
    }

    #[test]
    fn test_execute_command_reinstall() {
        let runner = MockRunner::new();
        let cmd = Commands::Reinstall {
            packages: vec!["pkg1".to_string()],
            all: true,
        };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(
            runner.get_calls(),
            vec![MockCall::Reinstall(vec!["pkg1".to_string()], true)]
        );
    }

    #[test]
    fn test_execute_command_upgrade() {
        let runner = MockRunner::new();
        let cmd = Commands::Upgrade {
            packages: vec![],
            dry_run: false,
        };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(runner.get_calls(), vec![MockCall::Upgrade(vec![], false)]);
    }

    #[test]
    fn test_execute_command_outdated() {
        let runner = MockRunner::new();
        let cmd = Commands::Outdated;
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(runner.get_calls(), vec![MockCall::Outdated]);
    }

    #[test]
    fn test_execute_command_update() {
        let runner = MockRunner::new();
        let cmd = Commands::Update;
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(runner.get_calls(), vec![MockCall::Update]);
    }

    #[cfg(feature = "wax")]
    #[test]
    fn test_execute_command_tap_bare_shorthand() {
        let runner = MockRunner::new();
        let cmd = Commands::Tap {
            tap: Some("undivisible/tap".to_string()),
            action: None,
        };
        execute_command(cmd, &runner).expect("execute_command failed");
        assert_eq!(
            runner.get_calls(),
            vec![MockCall::Tap(Some("undivisible/tap".to_string()), None)]
        );
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
    fn test_compute_upgrades() {
        use std::collections::HashMap;
        use crate::install::InstalledPackage;
        use crate::system::registry::{PackageIndex, PackageMetadata};

        let mut installed = HashMap::new();
        // Needs upgrade
        installed.insert("pkg_upgrade".to_string(), InstalledPackage {
            name: "pkg_upgrade".to_string(),
            version: "1.0.0".to_string(),
            install_date: 0,
            pinned: false,
        });
        // Up to date
        installed.insert("pkg_current".to_string(), InstalledPackage {
            name: "pkg_current".to_string(),
            version: "2.0.0".to_string(),
            install_date: 0,
            pinned: false,
        });
        // Pinned, should be ignored even if out of date
        installed.insert("pkg_pinned".to_string(), InstalledPackage {
            name: "pkg_pinned".to_string(),
            version: "1.0.0".to_string(),
            install_date: 0,
            pinned: true,
        });

        let pkgs = vec![
            PackageMetadata {
                name: "pkg_upgrade".to_string(),
                version: "1.1.0".to_string(),
                description: "".to_string(),
                download_url: "".to_string(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec![],
            },
            PackageMetadata {
                name: "pkg_current".to_string(),
                version: "2.0.0".to_string(),
                description: "".to_string(),
                download_url: "".to_string(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec![],
            },
            PackageMetadata {
                name: "pkg_pinned".to_string(),
                version: "1.1.0".to_string(),
                description: "".to_string(),
                download_url: "".to_string(),
                sha256: None,
                installed_size: 0,
                depends: vec![],
                provides: vec![],
            },
        ];
        let index = PackageIndex::new(pkgs);
        let targets = vec![
            "pkg_upgrade".to_string(),
            "pkg_current".to_string(),
            "pkg_pinned".to_string(),
        ];

        let upgrades = compute_upgrades(&targets, &installed, &index);

        assert_eq!(upgrades.len(), 1, "Only one package should be upgraded");
        assert_eq!(upgrades[0].0.name, "pkg_upgrade");
        assert_eq!(upgrades[0].0.version, "1.1.0");
        assert_eq!(upgrades[0].1, "1.0.0");
    }
}

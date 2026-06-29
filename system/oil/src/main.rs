mod error;
mod install;
mod signal;
mod system;

use clap::{Parser, Subcommand};
use error::Result;
use std::io::{Read, Write};
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

trait CommandRunner {
    fn search(&self, query: String) -> Result<()>;
    fn info(&self, formula: String) -> Result<()>;
    fn install(&self, packages: Vec<String>, dry_run: bool) -> Result<()>;
    fn uninstall(&self, formulae: Vec<String>, all: bool) -> Result<()>;
    fn reinstall(&self, packages: Vec<String>, all: bool) -> Result<()>;
    fn upgrade(&self, packages: Vec<String>, dry_run: bool) -> Result<()>;
    fn outdated(&self) -> Result<()>;
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
}

fn execute_command<R: CommandRunner>(cmd: Commands, runner: &R) -> Result<()> {
    match cmd {
        Commands::Search { query } => runner.search(query),
        Commands::Info { formula } => runner.info(formula),
        Commands::Install { packages, dry_run } => runner.install(packages, dry_run),
        Commands::Uninstall { formulae, all } => runner.uninstall(formulae, all),
        Commands::Reinstall { packages, all } => runner.reinstall(packages, all),
        Commands::Upgrade { packages, dry_run } => runner.upgrade(packages, dry_run),
        Commands::Outdated => runner.outdated(),
    }
}

fn run_command(cmd: Commands) -> Result<()> {
    let runner = DefaultRunner;
    execute_command(cmd, &runner)
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

    let mut tmp = tempfile::NamedTempFile::new()
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

    #[derive(Debug, PartialEq, Clone)]
    enum MockCall {
        Search(String),
        Info(String),
        Install(Vec<String>, bool),
        Uninstall(Vec<String>, bool),
        Reinstall(Vec<String>, bool),
        Upgrade(Vec<String>, bool),
        Outdated,
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
}

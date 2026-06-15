mod api;
mod bottle;
mod builder;
mod cache;
mod cask;
mod commands;
mod deps;
mod discovery;
mod ecosystem_install;
mod error;
mod formula_parser;
mod install;
mod lockfile;
mod package_spec;
mod remote_search;
mod signal;
mod sudo;
mod system;
mod system_pm;
mod tap;
mod timing;
mod ui;
mod version;

use api::ApiClient;
use cache::Cache;
use clap::{CommandFactory, Parser, Subcommand};
use clap_complete::Shell;
use error::Result;
use std::time::Instant;
use tracing::Level;
use tracing_subscriber::fmt::writer::MakeWriterExt;
use version::OIL_VERSION;

fn should_refresh_state(command: &Commands) -> bool {
    !matches!(
        command,
        Commands::Completions { .. }
            | Commands::__RefreshState
            | Commands::Install { .. }
            | Commands::InstallCask { .. }
            | Commands::Uninstall { .. }
            | Commands::Reinstall { .. }
            | Commands::Postinstall { .. }
            | Commands::SelfUpdate { .. }
            | Commands::Upgrade { .. }
            | Commands::System { .. }
            | Commands::Path
            | Commands::Lock
            | Commands::Sync
            | Commands::Link { .. }
            | Commands::Unlink { .. }
            | Commands::Cleanup { .. }
            | Commands::Pin { .. }
            | Commands::Unpin { .. }
            | Commands::Tap { repair: true, .. }
            | Commands::Doctor { fix: true, .. }
            | Commands::Bundle { dry_run: false, .. }
    )
}

fn command_prints_timing(command: &Commands) -> bool {
    matches!(
        command,
        Commands::Update { .. }
            | Commands::Install { .. }
            | Commands::InstallCask { .. }
            | Commands::Uninstall { .. }
            | Commands::Reinstall { .. }
            | Commands::Upgrade { .. }
            | Commands::Outdated
            | Commands::Sync
            | Commands::Bundle { .. }
    )
}

async fn refresh_state_in_child_process() {
    let Ok(exe) = std::env::current_exe() else {
        return;
    };

    let _ = std::process::Command::new(exe)
        .arg("__refresh_state")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

async fn run_self_update(nightly: bool, force: bool, clean: bool, no_clean: bool) -> Result<()> {
    if clean && no_clean {
        return Err(error::OilError::InvalidInput(
            "Cannot specify both --clean and --no-clean".to_string(),
        ));
    }

    let channel = if nightly {
        commands::self_update::Channel::Nightly
    } else {
        commands::self_update::Channel::Stable
    };
    let nightly_cleanup = if nightly {
        if clean {
            Some(true)
        } else if no_clean {
            Some(false)
        } else {
            None
        }
    } else {
        None
    };

    commands::self_update::self_update(channel, force, nightly_cleanup).await
}

#[derive(Parser)]
#[command(name = "oil")]
#[command(version = OIL_VERSION)]
#[command(about = format!("oil v{} - native system package manager", OIL_VERSION), long_about = None)]
#[command(subcommand_required = false)]
struct Cli {
    /// Print oil version, paths, and active taps (read-only)
    #[arg(long, global = true)]
    info: bool,

    #[command(subcommand)]
    command: Option<Commands>,

    #[arg(short, long, global = true)]
    verbose: bool,

    #[arg(short, long, global = true, help = "Assume yes for all prompts")]
    yes: bool,

    #[arg(
        long,
        alias = "tta",
        alias = "time",
        global = true,
        help = "Show command duration in result output"
    )]
    time_to_action: bool,
}

#[derive(Subcommand)]
enum Commands {
    #[command(about = "Update formula index or wax itself")]
    Update {
        #[arg(
            help = "Optional shorthand: s/self for stable self-update, sn/self-nightly for GitHub HEAD"
        )]
        action: Option<String>,
        #[arg(
            short = 's',
            long = "self",
            help = "Update wax itself instead of formula index"
        )]
        update_self: bool,
        #[arg(short, long, help = "Use nightly build from GitHub (with --self)")]
        nightly: bool,
        #[arg(
            short,
            long,
            help = "Force reinstall even if on latest version (with --self)"
        )]
        force: bool,
        #[arg(
            long,
            help = "After nightly self-update, clean Cargo git cache for wax"
        )]
        clean: bool,
        #[arg(long, help = "After nightly self-update, keep Cargo git cache")]
        no_clean: bool,
    },

    #[command(about = "Update wax itself  [alias: self-up]")]
    #[command(name = "self-update")]
    #[command(visible_alias = "self-up")]
    SelfUpdate {
        #[arg(short, long, help = "Use nightly build from GitHub")]
        nightly: bool,
        #[arg(short, long, help = "Force reinstall even if on latest version")]
        force: bool,
        #[arg(
            long,
            help = "After nightly self-update, clean Cargo git cache for wax"
        )]
        clean: bool,
        #[arg(long, help = "After nightly self-update, keep Cargo git cache")]
        no_clean: bool,
    },

    #[command(
        about = "Search formulae, casks, and brew index  [alias: s, find]"
    )]
    #[command(visible_alias = "s")]
    #[command(alias = "find")]
    Search { query: String },

    #[command(about = "Show formula details  [alias: show]")]
    #[command(visible_alias = "show")]
    Info {
        formula: String,
        #[arg(long)]
        cask: bool,
    },

    #[command(about = "List installed packages  [alias: ls]")]
    #[command(visible_alias = "ls")]
    List {
        #[arg(help = "Filter: pre-fills the interactive search (TTY), or limits printed output")]
        query: Option<String>,
        #[arg(
            long,
            visible_alias = "updates",
            help = "Only show packages with available updates"
        )]
        upgradable: bool,
    },

    #[command(
        about = "Install formulae/casks or system packages  [alias: i, add]"
    )]
    #[command(visible_alias = "i")]
    #[command(alias = "add")]
    Install {
        #[arg(
            help = "Package name(s); prefix brew/ for Linuxbrew formulae, or plain name for auto-detect"
        )]
        packages: Vec<String>,
        #[arg(long)]
        dry_run: bool,
        #[arg(long)]
        cask: bool,
        #[arg(long, help = "Install to ~/.local/wax (no sudo required)")]
        user: bool,
        #[arg(long, help = "Install to system directory (may need sudo)")]
        global: bool,
        #[arg(long, help = "Build from source even if bottle available")]
        build_from_source: bool,
        #[arg(
            long,
            help = "Install the HEAD version (clones git repo, builds from source)"
        )]
        head: bool,
        #[arg(long = "no-script", help = "Skip automatic post-install scripts")]
        no_script: bool,
    },

    #[command(about = "Install casks  [alias: c]")]
    #[command(name = "cask")]
    #[command(visible_alias = "c")]
    InstallCask {
        #[arg(required = true, help = "Cask name(s) to install")]
        packages: Vec<String>,
        #[arg(long)]
        dry_run: bool,
        #[arg(long, help = "Install to ~/.local/wax (no sudo required)")]
        user: bool,
        #[arg(long, help = "Install to system directory (may need sudo)")]
        global: bool,
        #[arg(long = "no-script", help = "Skip automatic post-install scripts")]
        no_script: bool,
    },

    #[command(about = "Uninstall a formula or cask  [alias: ui, rm, remove]")]
    #[command(visible_alias = "ui")]
    #[command(alias = "rm")]
    #[command(alias = "remove")]
    #[command(alias = "delete")]
    Uninstall {
        #[arg(conflicts_with = "all", required_unless_present = "all", num_args = 1..)]
        formulae: Vec<String>,
        #[arg(long)]
        dry_run: bool,
        #[arg(long)]
        cask: bool,
        #[arg(long, help = "Uninstall all installed formulae")]
        all: bool,
    },

    #[command(about = "Reinstall a formula or cask  [alias: ri]")]
    #[command(visible_alias = "ri")]
    Reinstall {
        #[arg(conflicts_with = "all", required_unless_present = "all")]
        packages: Vec<String>,
        #[arg(long)]
        cask: bool,
        #[arg(long, help = "Reinstall all installed formulae and casks")]
        all: bool,
    },

    #[command(about = "Run post-installation steps for a package")]
    Postinstall {
        #[arg(help = "Formula name(s) to run post-install for")]
        formulae: Vec<String>,
        #[arg(long, help = "Install to ~/.local/wax")]
        user: bool,
        #[arg(long, help = "Install to system directory")]
        global: bool,
    },

    #[command(about = "Upgrade formulae to the latest version  [alias: up]")]
    #[command(visible_alias = "up")]
    Upgrade {
        #[arg(help = "Package name(s) to upgrade (upgrades all if omitted)")]
        packages: Vec<String>,
        #[arg(short = 's', long = "self", help = "Upgrade wax itself")]
        upgrade_self: bool,
        #[arg(short, long, help = "Use nightly build from GitHub (with --self)")]
        nightly: bool,
        #[arg(
            long,
            help = "After nightly self-update, clean Cargo git cache for wax"
        )]
        clean: bool,
        #[arg(long, help = "After nightly self-update, keep Cargo git cache")]
        no_clean: bool,
        #[arg(long)]
        dry_run: bool,
        #[arg(long, help = "Also upgrade Wax-managed system packages")]
        system: bool,
    },

    #[command(about = "Manage Wax-owned OS-level packages")]
    System {
        #[command(subcommand)]
        action: SystemAction,
    },

    #[command(about = "List packages with available updates")]
    Outdated,

    #[command(about = "Re-create symlinks for installed packages  [alias: ln]")]
    #[command(visible_alias = "ln")]
    Link {
        #[arg(required = true)]
        packages: Vec<String>,
    },

    #[command(about = "Remove symlinks for a package (keeps Cellar)")]
    Unlink {
        #[arg(required = true)]
        packages: Vec<String>,
    },

    #[command(about = "Remove old versions from the Cellar")]
    Cleanup {
        #[arg(long)]
        dry_run: bool,
    },

    #[command(about = "Show installed packages not required by any other package")]
    Leaves,

    #[command(about = "Show formulae that depend on a given formula")]
    Uses {
        formula: String,
        #[arg(long, help = "Only show installed dependents")]
        installed: bool,
    },

    #[command(about = "Show dependencies for a formula")]
    Deps {
        formula: String,
        #[arg(long, help = "Show as dependency tree")]
        tree: bool,
        #[arg(long, help = "Only show installed dependencies")]
        installed: bool,
    },

    #[command(about = "Pin a formula to its current version  [alias: pin list]")]
    Pin {
        #[command(subcommand)]
        pin_cmd: Option<PinCmd>,
        #[arg(help = "Package name(s) to pin (when not using `wax pin list`)")]
        packages: Vec<String>,
        #[arg(long, help = "List all pinned packages")]
        list: bool,
    },

    #[command(about = "Unpin a formula to allow upgrades")]
    Unpin {
        #[arg(required = true)]
        packages: Vec<String>,
    },

    #[command(about = "List experimental feature flags")]
    Features,

    #[command(about = "Show oil installation info (paths, version, active taps)")]
    OilInfo,

    #[command(about = "Print PATH export for oil's bin directory [alias: env]")]
    #[command(visible_alias = "env")]
    Path,

    #[command(about = "Generate lockfile from installed packages")]
    Lock,

    #[command(name = "__refresh_state", hide = true)]
    __RefreshState,

    #[command(about = "Install packages from lockfile")]
    Sync,

    #[command(about = "Manage custom taps  [alias: untap]")]
    Tap {
        #[arg(long, help = "Re-clone missing or broken taps")]
        repair: bool,
        #[command(subcommand)]
        action: Option<TapAction>,
    },

    #[command(about = "Check system for potential problems  [alias: dr]")]
    #[command(visible_alias = "dr")]
    Doctor {
        #[arg(long, help = "Automatically fix detected issues")]
        fix: bool,
        #[arg(
            long,
            alias = "deep",
            help = "Run full diagnostics, including slower network, bottle, and code-signature scans"
        )]
        full: bool,
    },

    #[command(about = "Install packages from a Oilfile (formulae, casks, cargo, uv)")]
    Bundle {
        #[arg(long, help = "Path to Oilfile (default: ./Oilfile.toml)")]
        file: Option<String>,
        #[arg(long)]
        dry_run: bool,
        #[command(subcommand)]
        action: Option<BundleAction>,
    },

    #[command(about = "Manage background services")]
    #[command(alias = "svc")]
    Services {
        #[command(subcommand)]
        action: Option<ServicesAction>,
    },

    #[command(about = "Open a formula's source repository")]
    #[command(alias = "src")]
    Source {
        #[arg(help = "Formula or cask name")]
        formula: String,
    },

    #[command(about = "Install shell completions (auto-detects shell)")]
    Completions {
        #[arg(
            value_enum,
            help = "Shell to generate completions for (auto-detected if omitted)"
        )]
        shell: Option<Shell>,
        #[arg(long, help = "Print completions to stdout instead of installing")]
        print: bool,
    },

    #[command(about = "Show why a package is installed  [alias: explain]")]
    #[command(alias = "explain")]
    Why {
        #[arg(help = "Package name")]
        formula: String,
    },

    #[command(about = "Check installed packages for issues (deprecated, disabled, outdated)")]
    Audit,
}

#[derive(Subcommand)]
enum SystemAction {
    #[command(about = "Search Wax system package registries")]
    Search {
        #[arg(help = "Package search query")]
        query: String,
        #[arg(long, default_value_t = 20, help = "Maximum number of results")]
        limit: usize,
    },
    #[command(about = "Upgrade Wax-managed system packages")]
    Upgrade,
    #[command(about = "Install Wax-managed system packages")]
    Install {
        #[arg(required = true, help = "Package name(s) to install")]
        packages: Vec<String>,
        #[arg(long = "no-script", help = "Skip automatic post-install scripts")]
        no_script: bool,
    },
    #[command(about = "Declare and install packages (adds to desired state)")]
    Add {
        #[arg(required = true, help = "Package name(s) to add")]
        packages: Vec<String>,
        #[arg(long = "no-script", help = "Skip automatic post-install scripts")]
        no_script: bool,
    },
    #[command(about = "Remove packages and drop from desired state")]
    Remove {
        #[arg(required = true, help = "Package name(s) to remove")]
        packages: Vec<String>,
    },
    #[command(about = "Converge live system to declared package set")]
    Sync,
    #[command(about = "Show current generation, distro, and package status")]
    Status,
    #[command(about = "List all system generations")]
    Generations,
    #[command(
        about = "Roll back to a previous generation  [alias: rb]",
        visible_alias = "rb"
    )]
    Rollback {
        #[arg(help = "Generation ID to roll back to (defaults to previous)")]
        generation: Option<u32>,
    },
}

#[derive(Subcommand)]
enum BundleAction {
    #[command(about = "Dump installed packages as a Oilfile")]
    Dump,
}

#[derive(Subcommand)]
enum ServicesAction {
    #[command(about = "List all services")]
    List,
    #[command(about = "Start a service")]
    Start {
        #[arg(help = "Formula name")]
        formula: String,
        #[arg(long, help = "Nice priority (-20 to 20)")]
        nice: Option<i32>,
    },
    #[command(about = "Stop a service")]
    Stop {
        #[arg(help = "Formula name")]
        formula: String,
    },
    #[command(about = "Restart a service")]
    Restart {
        #[arg(help = "Formula name")]
        formula: String,
        #[arg(long, help = "Nice priority (-20 to 20)")]
        nice: Option<i32>,
    },
}

#[derive(Subcommand)]
enum PinCmd {
    #[command(about = "List all pinned packages", visible_alias = "ls")]
    List,
}

#[derive(Subcommand)]
enum TapAction {
    #[command(about = "Add a custom tap")]
    Add {
        #[arg(help = "Tap specification: user/repo, Git URL, local directory, or .rb file path")]
        tap: String,
    },
    #[command(
        about = "Remove a custom tap",
        visible_alias = "rm",
        alias = "uninstall",
        alias = "delete"
    )]
    Remove {
        #[arg(help = "Tap specification: user/repo, Git URL, local directory, or .rb file path")]
        tap: String,
    },
    #[command(about = "List installed taps", visible_alias = "ls")]
    List,
    #[command(about = "Update a tap", visible_alias = "up")]
    Update {
        #[arg(help = "Tap specification: user/repo, Git URL, local directory, or .rb file path")]
        tap: String,
    },
    /// Bare `wax tap user/repo` — treated as an add.
    #[command(external_subcommand)]
    External(Vec<String>),
}

fn init_logging(verbose: bool) -> Result<()> {
    let log_dir = ui::dirs::oil_logs_dir()?;

    std::fs::create_dir_all(&log_dir)?;

    let log_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_dir.join("oil.log"))?;

    let level = if verbose { Level::DEBUG } else { Level::INFO };

    tracing_subscriber::fmt()
        .with_max_level(level)
        .with_writer(log_file.with_max_level(Level::TRACE))
        .with_ansi(false)
        .init();

    Ok(())
}

async fn handle_system_upgrade() -> Result<()> {
    match system::SystemManager::detect().await? {
        Some(mgr) => mgr.upgrade_all().await,
        None => Err(error::OilError::PlatformNotSupported(
            "No supported wax system registry found".to_string(),
        )),
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let action_timer = Instant::now();
    let cli = Cli::parse();

    if let Some(ref command) = cli.command {
        if should_refresh_state(command) {
            refresh_state_in_child_process().await;
        }
    }

    signal::install_handler();
    init_logging(cli.verbose)?;

    if cli.info {
        return commands::oil_info::oil_info();
    }

    let Some(command) = cli.command else {
        let mut cmd = Cli::command();
        let _ = cmd.print_help();
        std::process::exit(2);
    };
    let command_prints_own_timing = command_prints_timing(&command);

    let api_client = ApiClient::new();
    let cache = Cache::new()?;
    timing::set_enabled(cli.time_to_action);

    let result = match command {
        Commands::Update {
            action,
            mut update_self,
            mut nightly,
            force,
            clean,
            no_clean,
        } => {
            if let Some(action) = action {
                match action.as_str() {
                    "s" | "self" => update_self = true,
                    "sn" | "self-nightly" => {
                        update_self = true;
                        nightly = true;
                    }
                    other => {
                        return Err(error::OilError::InvalidInput(format!(
                            "Unknown update shorthand '{other}' (use s/self or sn/self-nightly)"
                        )));
                    }
                }
            }

            if update_self {
                run_self_update(nightly, force, clean, no_clean).await
            } else {
                commands::update::update(&api_client, &cache).await
            }
        }
        Commands::SelfUpdate {
            nightly,
            force,
            clean,
            no_clean,
        } => run_self_update(nightly, force, clean, no_clean).await,
        Commands::Search { query } => commands::search::search(&cache, &query).await,
        Commands::Info { formula, cask } => {
            commands::info::info(&api_client, &cache, &formula, cask).await
        }
        Commands::List { query, upgradable } => {
            commands::list::list(&cache, query, upgradable).await
        }
        Commands::Install {
            packages,
            dry_run,
            cask,
            user,
            global,
            build_from_source,
            head,
            no_script,
        } => {
            if packages.is_empty() && !cask {
                // No packages specified — sync from lockfile like `npm install`
                commands::sync::sync(&cache).await
            } else {
                commands::install::install(
                    &cache,
                    &packages,
                    dry_run,
                    cask,
                    user,
                    global,
                    build_from_source,
                    head,
                    !no_script,
                )
                .await
            }
        }
        Commands::InstallCask {
            packages,
            dry_run,
            user,
            global,
            no_script,
        } => {
            commands::install::install(
                &cache, &packages, dry_run, true, user, global, false, false, !no_script,
            )
            .await
        }
        Commands::Uninstall {
            formulae,
            dry_run,
            cask,
            all,
        } => commands::uninstall::uninstall(&cache, &formulae, dry_run, cask, cli.yes, all).await,
        Commands::Reinstall {
            packages,
            cask,
            all,
        } => commands::reinstall::reinstall(&cache, &packages, cask, all).await,
        Commands::Postinstall {
            formulae,
            user,
            global,
        } => commands::install::postinstall(&cache, &formulae, user, global).await,
        Commands::Upgrade {
            packages,
            upgrade_self,
            nightly,
            clean,
            no_clean,
            dry_run,
            system,
        } => {
            if upgrade_self {
                run_self_update(nightly, false, clean, no_clean).await?;
                return Ok(());
            }

            let explicit_packages_requested = !packages.is_empty();

            commands::upgrade::upgrade(&cache, &packages, dry_run).await?;
            if system {
                handle_system_upgrade().await?;
            }

            // Only check for wax self-update after a full upgrade run.
            // For explicit package upgrades (e.g. `wax up codex`), skip this
            // to avoid unrelated self-update output in command results.
            if !explicit_packages_requested {
                commands::self_update::self_update(
                    commands::self_update::Channel::Stable,
                    false,
                    None,
                )
                .await?;
            }

            Ok(())
        }
        Commands::System { action } => match action {
            SystemAction::Search { query, limit } => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.search(&query, limit).await,
                None => {
                    eprintln!("no supported system package manager found");
                    Ok(())
                }
            },
            SystemAction::Upgrade => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.upgrade_all().await,
                None => handle_system_upgrade().await,
            },
            SystemAction::Install {
                packages,
                no_script,
            } => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.install_with_options(&packages, !no_script).await,
                None => Err(crate::error::OilError::PlatformNotSupported(
                    "No supported wax system registry found".to_string(),
                )),
            },
            SystemAction::Add {
                packages,
                no_script,
            } => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.add_with_options(&packages, !no_script).await,
                None => Err(crate::error::OilError::PlatformNotSupported(
                    "No supported wax system registry found".to_string(),
                )),
            },
            SystemAction::Remove { packages } => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.remove(&packages).await,
                None => Err(crate::error::OilError::PlatformNotSupported(
                    "No supported system package manager found".to_string(),
                )),
            },
            SystemAction::Sync => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.sync_declared().await,
                None => Err(crate::error::OilError::PlatformNotSupported(
                    "No supported system package manager found".to_string(),
                )),
            },
            SystemAction::Status => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.status().await,
                None => {
                    eprintln!("no supported system package manager found");
                    Ok(())
                }
            },
            SystemAction::Generations => match system::SystemManager::detect().await? {
                Some(mgr) => {
                    let gens = mgr.list_generations().await?;
                    if gens.is_empty() {
                        println!("no generations yet");
                        return Ok(());
                    }
                    let current_id = mgr.current_generation().await?.map(|g| g.id);
                    for gen in &gens {
                        let marker = if Some(gen.id) == current_id {
                            console::style("▶").green().to_string()
                        } else {
                            console::style(" ").dim().to_string()
                        };
                        println!(
                            "{} gen-{:04}  {:>4} pkgs  {}  {}",
                            marker,
                            console::style(gen.id).bold(),
                            gen.packages.len(),
                            console::style(gen.age_string()).dim(),
                            console::style(&gen.reason).cyan()
                        );
                    }
                    Ok(())
                }
                None => {
                    eprintln!("no supported system package manager found");
                    Ok(())
                }
            },
            SystemAction::Rollback { generation } => match system::SystemManager::detect().await? {
                Some(mgr) => mgr.rollback(generation).await,
                None => Err(crate::error::OilError::PlatformNotSupported(
                    "No supported system package manager found".to_string(),
                )),
            },
        },
        Commands::Outdated => commands::outdated::outdated(&cache).await,
        Commands::Link { packages } => commands::link::link(&packages).await,
        Commands::Unlink { packages } => commands::link::unlink(&packages).await,
        Commands::Cleanup { dry_run } => commands::cleanup::cleanup(dry_run).await,
        Commands::Leaves => commands::leaves::leaves(&cache).await,
        Commands::Uses { formula, installed } => {
            commands::uses::uses(&cache, &formula, installed).await
        }
        Commands::Deps {
            formula,
            tree,
            installed,
        } => commands::show_deps::deps(&cache, &formula, tree, installed).await,
        Commands::Pin {
            pin_cmd,
            packages,
            list,
        } => {
            if list || matches!(pin_cmd, Some(PinCmd::List)) {
                commands::pin::list_pinned().await
            } else if packages.is_empty() {
                Err(crate::error::OilError::InvalidInput(
                    "specify package(s) to pin, or run `wax pin list` / `wax pin --list`"
                        .to_string(),
                ))
            } else {
                commands::pin::pin(&packages).await
            }
        }
        Commands::Unpin { packages } => commands::pin::unpin(&packages).await,
        Commands::Lock => commands::lock::lock(&cache).await,
        Commands::__RefreshState => commands::refresh::refresh(&cache).await,
        Commands::Sync => commands::sync::sync(&cache).await,
        Commands::Tap { action, repair } => commands::tap::tap(action, repair, Some(&cache)).await,
        Commands::Doctor { fix, full } => commands::doctor::doctor(&cache, fix, full).await,
        Commands::Bundle {
            file,
            dry_run,
            action,
        } => match action {
            Some(BundleAction::Dump) => commands::bundle::bundle_dump(&cache).await,
            None => commands::bundle::bundle(&cache, file.as_deref(), dry_run).await,
        },
        Commands::Services { action } => match action {
            Some(ServicesAction::List) | None => commands::services::services_list().await,
            Some(ServicesAction::Start { formula, nice }) => {
                commands::services::services_start(&formula, nice).await
            }
            Some(ServicesAction::Stop { formula }) => {
                commands::services::services_stop(&formula).await
            }
            Some(ServicesAction::Restart { formula, nice }) => {
                commands::services::services_restart(&formula, nice).await
            }
        },
        Commands::Source { formula } => commands::source::source(&cache, &formula).await,
        Commands::Completions { shell, print } => commands::completions::completions(shell, print),
        Commands::Why { formula } => {
            commands::info::info(&api_client, &cache, &formula, false).await
        }
        Commands::Audit => commands::audit::audit(&cache).await,
        Commands::Features => commands::features::features(),
                Commands::Path => commands::path::oil_path(),
                Commands::OilInfo => commands::oil_info::oil_info(),
    };

    if let Err(e) = result {
        use console::style;
        use error::OilError;

        let prefix = style("error:").red().bold();
        match e {
            OilError::Interrupted => {
                eprintln!("\n{} interrupted", style("✗").red());
                std::process::exit(130);
            }
            OilError::NotInstalled(pkg) => {
                eprintln!("{} {} is not installed", prefix, style(&pkg).magenta());
            }
            OilError::FormulaNotFound(pkg) => {
                eprintln!("{} formula not found: {}", prefix, style(&pkg).magenta());
            }
            OilError::CaskNotFound(pkg) => {
                eprintln!("{} cask not found: {}", prefix, style(&pkg).magenta());
            }
            _ => {
                eprintln!("{} {}", prefix, e);
            }
        }
        std::process::exit(1);
    }

    if cli.time_to_action && !command_prints_own_timing {
        println!("{}", timing::elapsed_text(action_timer.elapsed()));
    }

    Ok(())
}

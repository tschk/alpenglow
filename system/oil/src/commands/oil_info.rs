use crate::bottle::homebrew_prefix;
use crate::error::Result;
use crate::ui::dirs;
use crate::version::OIL_VERSION;
use console::style;

pub fn oil_info() -> Result<()> {
    let prefix = homebrew_prefix();
    let cellar = prefix.join("Cellar");
    let taps_dir = prefix.join("Library/Taps");
    let cache_dir = dirs::oil_cache_dir().unwrap_or_else(|_| prefix.join("var/cache/wax"));
    let data_dir = dirs::oil_dir().unwrap_or_else(|_| prefix.join("etc/wax"));
    let log_file = dirs::oil_logs_dir()
        .map(|d| d.join("oil.log"))
        .unwrap_or_else(|_| data_dir.join("logs/oil.log"));

    println!();
    println!(
        "{} {}",
        style("oil").bold().magenta(),
        style(OIL_VERSION).dim()
    );
    println!();

    let row = |label: &str, value: &str| {
        println!("  {:<22} {}", style(label).dim(), value);
    };

    row("Version:", OIL_VERSION);
    row("Prefix:", &prefix.display().to_string());
    row("Cellar:", &cellar.display().to_string());
    row("Taps:", &taps_dir.display().to_string());
    row("Cache:", &cache_dir.display().to_string());
    row("Data:", &data_dir.display().to_string());
    row("Log file:", &log_file.display().to_string());
    row("OS:", std::env::consts::OS);
    row("Arch:", std::env::consts::ARCH);

    // Active taps
    if taps_dir.exists() {
        let mut tap_names = Vec::new();
        if let Ok(vendors) = std::fs::read_dir(&taps_dir) {
            for vendor in vendors.flatten() {
                if let Ok(repos) = std::fs::read_dir(vendor.path()) {
                    for repo in repos.flatten() {
                        tap_names.push(format!(
                            "{}/{}",
                            vendor.file_name().to_string_lossy(),
                            repo.file_name().to_string_lossy()
                        ));
                    }
                }
            }
        }
        tap_names.sort();
        if !tap_names.is_empty() {
            row("Taps (active):", &tap_names.join(", "));
        }
    }

    println!();
    Ok(())
}

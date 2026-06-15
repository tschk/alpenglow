//! Host package ecosystem detection and read-only inventory helpers.
//!
//! Wax-managed system packages must not delegate install/remove/upgrade to host
//! package managers. This module may detect available tools and query installed
//! inventory, but mutating host-PM operations intentionally return unsupported.

use crate::error::{Result, OilError};

use std::path::Path;
use tokio::process::Command;
use tracing::debug;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemSearchResult {
    pub name: String,
    pub version: Option<String>,
    pub summary: Option<String>,
}

/// A detected system package manager.
#[derive(Debug, Clone, PartialEq)]
pub enum SystemPm {
    Brew,
    Apt,
    Dnf,
    Pacman,
    Apk,
    Zypper,
    Emerge,
    Yum,
    Xbps,
    Nix,
}

impl SystemPm {
    /// Human-readable name.
    pub fn name(&self) -> &'static str {
        match self {
            Self::Brew => "brew",
            Self::Apt => "apt",
            Self::Dnf => "dnf",
            Self::Pacman => "pacman",
            Self::Apk => "apk",
            Self::Zypper => "zypper",
            Self::Emerge => "emerge",
            Self::Yum => "yum",
            Self::Xbps => "xbps-install",
            Self::Nix => "nix-env",
        }
    }

    /// Detect the appropriate package manager for this distro.
    /// Reads os-release first, falls back to binary detection.
    pub async fn detect() -> Option<Self> {
        if cfg!(target_os = "macos") {
            return None;
        }

        // Try os-release based distro matching first
        let os_release = std::fs::read_to_string("/etc/os-release").unwrap_or_default();
        let distro_id = Self::parse_os_release_field(&os_release, "ID");
        let distro_like = Self::parse_os_release_field(&os_release, "ID_LIKE");

        let matched = Self::match_distro(&distro_id, &distro_like);
        if let Some(pm) = matched {
            debug!("Detected distro: {} ({}), using {}", distro_id, distro_like, pm.name());
            return Some(pm);
        }

        // Fallback: binary detection (works in containers, chroots)
        let candidates: &[(&str, Self)] = &[
                #[cfg(any(feature = "system-apt", feature = "system-all"))]
                ("apt-get", Self::Apt),
                #[cfg(any(feature = "system-dnf", feature = "system-all"))]
                ("dnf", Self::Dnf),
                #[cfg(any(feature = "system-pacman", feature = "system-all"))]
                ("pacman", Self::Pacman),
                #[cfg(any(feature = "system-apk", feature = "system-all"))]
                ("apk", Self::Apk),
                ("zypper", Self::Zypper),
                ("emerge", Self::Emerge),
                #[cfg(any(feature = "system-dnf", feature = "system-all"))]
                ("yum", Self::Yum),
                #[cfg(any(feature = "system-xbps", feature = "system-all"))]
                ("xbps-install", Self::Xbps),
                ("nix-env", Self::Nix),
                #[cfg(any(feature = "system-nix", feature = "system-all"))]
                ("nix", Self::Nix),
            ];

            for (bin, pm) in candidates {
                if which(bin).await {
                    debug!("Detected package manager binary: {}", bin);
                    return Some(pm.clone());
                }
            }

        None
    }

    /// Match a distro ID/ID_LIKE to a package manager.
    fn match_distro(id: &str, id_like: &str) -> Option<Self> {
        let all = format!("{} {}", id, id_like).to_lowercase();
        #[cfg(any(feature = "system-apt", feature = "system-all"))]
        if all.contains("debian") || all.contains("ubuntu") || all.contains("mint") {
            return Some(Self::Apt);
        }
        #[cfg(any(feature = "system-dnf", feature = "system-all"))]
        if all.contains("fedora") || all.contains("rhel") || all.contains("centos") {
            return Some(Self::Dnf);
        }
        #[cfg(any(feature = "system-pacman", feature = "system-all"))]
        if all.contains("arch") || all.contains("manjaro") {
            return Some(Self::Pacman);
        }
        #[cfg(any(feature = "system-apk", feature = "system-all"))]
        if all.contains("alpine") || all.contains("chimera") {
            return Some(Self::Apk);
        }
        #[cfg(any(feature = "system-xbps", feature = "system-all"))]
        #[cfg(any(feature = "system-nix", feature = "system-all"))]
        if all.contains("nixos") {
            return Some(Self::Nix);
        }
        if all.contains("void") {
            return Some(Self::Xbps);
        }
        None
    }

    fn parse_os_release_field(os_release: &str, field: &str) -> String {
        os_release.lines().find_map(|line| {
            let prefix = format!("{}={}", field, "\"");
            if let Some(val) = line.strip_prefix(&prefix) {
                Some(val.trim_end_matches('"').to_string())
            } else {
                let prefix = format!("{}={}", field, "");
                line.strip_prefix(&prefix).map(|v| v.trim().to_string())
            }
        }).unwrap_or_default()
    }

    /// List packages currently installed by this package manager.
    pub async fn list_installed(&self) -> Result<Vec<(String, Option<String>)>> {
        match self {
            Self::Brew => list_installed_with("brew", &["list", "--versions"]).await,
            Self::Apt => {
                list_installed_with("dpkg-query", &["-W", r#"-f=${Package}\t${Version}\n"#]).await
            }
            Self::Dnf | Self::Yum | Self::Zypper => {
                list_installed_with(
                    "rpm",
                    &["-qa", "--queryformat", "%{NAME}\t%{VERSION}-%{RELEASE}\n"],
                )
                .await
            }
            Self::Pacman => list_installed_with("pacman", &["-Q"]).await,
            Self::Apk => list_installed_with("apk", &["info", "-v"]).await,
            Self::Emerge => list_installed_with("qlist", &["-ICv"]).await,
            Self::Xbps => list_installed_with("xbps-query", &["-l"]).await,
            Self::Nix => list_installed_with("nix-env", &["-q"]).await,
        }
    }

    #[expect(
        dead_code,
        reason = "host package search disabled; direct registry search is used"
    )]
    pub async fn search(&self, query: &str, limit: usize) -> Result<Vec<SystemSearchResult>> {
        let output = match self {
            Self::Brew => run_capture("brew", &["search", query]).await?,
            Self::Apt => run_capture("apt-cache", &["search", query]).await?,
            Self::Dnf => run_capture("dnf", &["search", query]).await?,
            Self::Pacman => run_capture("pacman", &["-Ss", query]).await?,
            Self::Apk => run_capture("apk", &["search", query]).await?,
            Self::Zypper => run_capture("zypper", &["--non-interactive", "search", query]).await?,
            Self::Emerge => run_capture("emerge", &["--search", query]).await?,
            Self::Yum => run_capture("yum", &["search", query]).await?,
            Self::Xbps => run_capture("xbps-query", &["-Rs", query]).await?,
            Self::Nix => run_capture("nix-env", &["-qaP", query]).await?,
        };

        Ok(parse_search_results(self, &output, limit))
    }

    #[expect(dead_code, reason = "mutating host-PM operations are disabled")]
    pub async fn remove(&self, _packages: &[String]) -> Result<()> {
        Err(OilError::PlatformNotSupported(format!(
            "oil does not delegate system removals to {}; wax removes files from its own manifests",
            self.name()
        )))
    }

    /// Linux cask installation is disabled for now. Wax should not silently
    /// hand casks off to snap/flatpak/native package managers because that
    /// breaks the Wax-owned install/state/manifest model.
    pub async fn install_cask(&self, cask_name: &str) -> Result<()> {
        Err(OilError::PlatformNotSupported(format!(
            "Linux cask install for '{}' is disabled: oil does not delegate installs to other package managers",
            cask_name
        )))
    }
}

/// Check if a binary exists on PATH.
async fn which(bin: &str) -> bool {
    if bin.contains(std::path::MAIN_SEPARATOR) {
        return is_executable(Path::new(bin));
    }

    let Some(paths) = std::env::var_os("PATH") else {
        return false;
    };

    std::env::split_paths(&paths).any(|dir| is_executable(&dir.join(bin)))
}

fn is_executable(path: &Path) -> bool {
    let Ok(metadata) = std::fs::metadata(path) else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }

    #[cfg(not(unix))]
    {
        true
    }
}

async fn run_capture(program: &str, args: &[&str]) -> Result<String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .await
        .map_err(|e| OilError::InstallError(format!("Failed to run {}: {}", program, e)))?;

    if !output.status.success() {
        return Err(OilError::InstallError(format!(
            "{} exited with status {}",
            program,
            output.status.code().unwrap_or(-1)
        )));
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn parse_search_results(pm: &SystemPm, output: &str, limit: usize) -> Vec<SystemSearchResult> {
    let mut results: Vec<SystemSearchResult> = Vec::new();
    let mut pending_pacman: Option<usize> = None;
    let mut pending_emerge: Option<usize> = None;

    for raw in output.lines() {
        let line = raw.trim_end();
        if line.trim().is_empty() {
            continue;
        }

        if let Some(idx) = pending_pacman.take() {
            if raw.starts_with(' ') || raw.starts_with('\t') {
                results[idx].summary = Some(line.trim().to_string());
                if results.len() >= limit {
                    break;
                }
                continue;
            }
        }

        if let Some(idx) = pending_emerge.take() {
            if let Some(summary) = line.trim().strip_prefix("Description:") {
                results[idx].summary = Some(summary.trim().to_string());
                if results.len() >= limit {
                    break;
                }
                continue;
            }
        }

        let parsed = match pm {
            SystemPm::Apt => parse_dash_summary(line),
            SystemPm::Dnf | SystemPm::Yum => parse_colon_summary(line),
            SystemPm::Pacman => parse_pacman_search_line(line),
            SystemPm::Apk => parse_apk_search_line(line),
            SystemPm::Zypper => parse_zypper_search_line(line),
            SystemPm::Emerge => parse_emerge_search_line(line),
            SystemPm::Xbps => parse_xbps_search_line(line),
            SystemPm::Nix => parse_nix_search_line(line),
            SystemPm::Brew => parse_plain_name(line),
        };

        if let Some(result) = parsed {
            results.push(result);
            let idx = results.len() - 1;
            if matches!(pm, SystemPm::Pacman) {
                pending_pacman = Some(idx);
            }
            if matches!(pm, SystemPm::Emerge) {
                pending_emerge = Some(idx);
            }
            if results.len() >= limit && !matches!(pm, SystemPm::Pacman | SystemPm::Emerge) {
                break;
            }
        }
    }

    results.truncate(limit);
    results
}

fn parse_plain_name(line: &str) -> Option<SystemSearchResult> {
    let name = line.split_whitespace().next()?.trim();
    if name.is_empty() {
        return None;
    }
    Some(SystemSearchResult {
        name: name.to_string(),
        version: None,
        summary: None,
    })
}

fn parse_dash_summary(line: &str) -> Option<SystemSearchResult> {
    let (left, summary) = line.split_once(" - ").unwrap_or((line, ""));
    let name = left.split_whitespace().next()?.trim();
    if name.is_empty() {
        return None;
    }
    Some(SystemSearchResult {
        name: name.to_string(),
        version: None,
        summary: non_empty(summary),
    })
}

fn parse_colon_summary(line: &str) -> Option<SystemSearchResult> {
    if line.starts_with("Last metadata") || line.starts_with("===") {
        return None;
    }
    let (left, summary) = line.split_once(" : ").unwrap_or((line, ""));
    let name = left.split_whitespace().next()?.trim();
    if name.is_empty() {
        return None;
    }
    Some(SystemSearchResult {
        name: name.to_string(),
        version: None,
        summary: non_empty(summary),
    })
}

fn parse_pacman_search_line(line: &str) -> Option<SystemSearchResult> {
    let (repo_name, rest) = line.split_once(' ')?;
    let name = repo_name.split_once('/')?.1;
    let version = rest.split_whitespace().next().map(|s| s.to_string());
    Some(SystemSearchResult {
        name: name.to_string(),
        version,
        summary: None,
    })
}

fn parse_apk_search_line(line: &str) -> Option<SystemSearchResult> {
    let mut parts = line.splitn(2, ' ');
    let name_version = parts.next()?.trim();
    let summary = parts.next().and_then(non_empty);
    let (name, version) = split_name_version(name_version);
    Some(SystemSearchResult {
        name,
        version,
        summary,
    })
}

fn parse_zypper_search_line(line: &str) -> Option<SystemSearchResult> {
    if line.starts_with('S') || line.starts_with('-') {
        return None;
    }
    let cols: Vec<&str> = line.split('|').map(|s| s.trim()).collect();
    if cols.len() < 3 {
        return parse_plain_name(line);
    }
    let version = if cols.len() > 3 {
        non_empty(cols[3])
    } else {
        None
    };
    Some(SystemSearchResult {
        name: cols[1].to_string(),
        version,
        summary: non_empty(cols[2]),
    })
}

fn parse_emerge_search_line(line: &str) -> Option<SystemSearchResult> {
    let name = line.strip_prefix('*')?.trim();
    if name.is_empty() {
        return None;
    }
    Some(SystemSearchResult {
        name: name.to_string(),
        version: None,
        summary: None,
    })
}

fn parse_xbps_search_line(line: &str) -> Option<SystemSearchResult> {
    let rest = line
        .strip_prefix("[*] ")
        .or_else(|| line.strip_prefix("[-] "))
        .unwrap_or(line);
    let mut parts = rest.splitn(2, ' ');
    let name_version = parts.next()?.trim();
    let summary = parts.next().and_then(non_empty);
    let (name, version) = split_name_version(name_version);
    Some(SystemSearchResult {
        name,
        version,
        summary,
    })
}

fn parse_nix_search_line(line: &str) -> Option<SystemSearchResult> {
    let mut parts = line.split_whitespace();
    let attr = parts.next()?;
    let name_version = parts.next().unwrap_or(attr);
    let (name, version) = split_name_version(name_version);
    Some(SystemSearchResult {
        name,
        version,
        summary: None,
    })
}

fn split_name_version(name_version: &str) -> (String, Option<String>) {
    if let Some((name, version)) = name_version.rsplit_once('-') {
        if version
            .chars()
            .next()
            .map(|c| c.is_ascii_digit())
            .unwrap_or(false)
        {
            return (name.to_string(), Some(version.to_string()));
        }
    }
    (name_version.to_string(), None)
}

fn non_empty(s: &str) -> Option<String> {
    let s = s.trim();
    if s.is_empty() {
        None
    } else {
        Some(s.to_string())
    }
}

async fn list_installed_with(
    program: &str,
    args: &[&str],
) -> Result<Vec<(String, Option<String>)>> {
    let output = Command::new(program).args(args).output().await;
    let Ok(output) = output else {
        return Ok(Vec::new());
    };
    if !output.status.success() {
        return Ok(Vec::new());
    }

    let mut packages = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let (name, version) = if program == "apk" {
            if let Some(idx) = line.rfind('-') {
                let name = &line[..idx];
                let version = &line[idx + 1..];
                if version
                    .chars()
                    .next()
                    .map(|c| c.is_ascii_digit())
                    .unwrap_or(false)
                {
                    (name.to_string(), Some(version.to_string()))
                } else {
                    (line.to_string(), None)
                }
            } else {
                (line.to_string(), None)
            }
        } else if program == "xbps-query" {
            let rest = line.strip_prefix("ii ").unwrap_or(line);
            if let Some((name, version)) = rest.rsplit_once('-') {
                (name.to_string(), Some(version.to_string()))
            } else {
                (rest.to_string(), None)
            }
        } else if program == "nix-env" {
            if let Some((name, version)) = line.rsplit_once('-') {
                (name.to_string(), Some(version.to_string()))
            } else {
                (line.to_string(), None)
            }
        } else if let Some((name, version)) = line.split_once('\t') {
            (name.trim().to_string(), Some(version.trim().to_string()))
        } else {
            let mut split = line.split_whitespace();
            let Some(name) = split.next() else {
                continue;
            };
            (name.to_string(), split.next().map(|s| s.to_string()))
        };

        if name.is_empty() {
            continue;
        }
        packages.push((name, version));
    }

    packages.sort_by(|a, b| a.0.cmp(&b.0));
    packages.dedup_by(|a, b| a.0 == b.0);
    Ok(packages)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_apt_search_results() {
        let out = "ripgrep - recursively searches directories for a regex pattern\n";
        let results = parse_search_results(&SystemPm::Apt, out, 20);
        assert_eq!(
            results,
            vec![SystemSearchResult {
                name: "ripgrep".into(),
                version: None,
                summary: Some("recursively searches directories for a regex pattern".into()),
            }]
        );
    }

    #[test]
    fn parses_pacman_search_results() {
        let out = "extra/ripgrep 14.1.1-1\n    A search tool that combines ag with grep\n";
        let results = parse_search_results(&SystemPm::Pacman, out, 20);
        assert_eq!(
            results,
            vec![SystemSearchResult {
                name: "ripgrep".into(),
                version: Some("14.1.1-1".into()),
                summary: Some("A search tool that combines ag with grep".into()),
            }]
        );
    }

    #[test]
    fn parses_nix_search_results() {
        let out = "nixpkgs.ripgrep ripgrep-14.1.1\n";
        let results = parse_search_results(&SystemPm::Nix, out, 20);
        assert_eq!(
            results,
            vec![SystemSearchResult {
                name: "ripgrep".into(),
                version: Some("14.1.1".into()),
                summary: None,
            }]
        );
    }
}

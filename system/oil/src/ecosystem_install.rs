//! Route `wax install` to Homebrew-style formulae (Linuxbrew).

use crate::cache::Cache;
use crate::error::{Result, OilError};
use crate::package_spec::{Ecosystem, PackageSpec};

/// Returns `true` if this package was fully handled (no batch install needed).
/// On Linux, only brew/ prefix forces Homebrew. Everything else is a system install.
pub async fn install_one_qualified(
    cache: &Cache,
    raw: &str,
    dry_run: bool,
    cask: bool,
) -> Result<bool> {
    let spec = crate::package_spec::parse_package_spec(raw);
    validate_qualified_inner(&spec)?;

    if cask {
        return Ok(false);
    }

    // If explicitly brew, route to Homebrew-style install (not handled here)
    if spec.force == Some(Ecosystem::Brew) || !cfg!(target_os = "windows") {
        let _ = cache;
        return Ok(false);
    }

    if let Some(forced) = spec.force {
        install_forced(forced, &spec.name, dry_run).await?;
        return Ok(true);
    }

    Err(OilError::FormulaNotFound(format!(
        "no matching package '{}' in brew index",
        spec.name
    )))
}

fn validate_qualified_inner(spec: &PackageSpec) -> Result<()> {
    let n = spec.name.trim();
    if n.is_empty() {
        return Err(OilError::InvalidInput(
            "empty package name after prefix".into(),
        ));
    }
    if spec.force.is_some() && n.contains('/') {
        return Err(OilError::InvalidInput(
            "names with '/' after a brew prefix are not supported".into(),
        ));
    }
    if !n.chars().all(|c| c.is_alphanumeric() || "-_.+".contains(c)) {
        return Err(OilError::InvalidInput(format!(
            "unsupported characters in package id: {n}"
        )));
    }
    Ok(())
}

async fn install_forced(eco: Ecosystem, name: &str, dry_run: bool) -> Result<()> {
    if dry_run {
        println!("dry-run: would install via {} → {}", eco.label(), name);
        return Ok(());
    }

    match eco {
        Ecosystem::Brew => Ok(()),
    }
}

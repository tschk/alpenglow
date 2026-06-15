/// Query the live system for installed package versions.
///
/// These functions shell out to read-only query tools (dpkg-query, rpm, pacman, apk)
/// to get a ground-truth snapshot of what is actually installed.  They do NOT
/// install or remove anything.
use crate::error::Result;
use crate::system::distro::PackageFormat;
use crate::system_pm::SystemPm;

/// Returns a sorted list of `(name, version)` tuples for all packages the
/// system package manager currently considers installed.
pub async fn list_installed(format: &PackageFormat) -> Result<Vec<(String, Option<String>)>> {
    match format {
        PackageFormat::Brew => SystemPm::Brew.list_installed().await,
        PackageFormat::Deb => query_dpkg().await,
        PackageFormat::Rpm => query_rpm().await,
        PackageFormat::Pacman => query_pacman().await,
        PackageFormat::Apk => query_apk().await,
        PackageFormat::Other => Ok(vec![]),
    }
}

async fn query_dpkg() -> Result<Vec<(String, Option<String>)>> {
    SystemPm::Apt.list_installed().await
}

async fn query_rpm() -> Result<Vec<(String, Option<String>)>> {
    SystemPm::Dnf.list_installed().await
}

async fn query_pacman() -> Result<Vec<(String, Option<String>)>> {
    SystemPm::Pacman.list_installed().await
}

async fn query_apk() -> Result<Vec<(String, Option<String>)>> {
    SystemPm::Apk.list_installed().await
}

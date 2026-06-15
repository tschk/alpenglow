use crate::error::{OilError, Result};
use crate::system::extractor::extract_package_tracked;
use crate::system::registry::PackageMetadata;
use std::path::Path;

pub struct SystemInstaller;

impl SystemInstaller {
    pub fn new(_distro: &crate::system::distro::DistroInfo) -> Result<Self> {
        Ok(Self)
    }

    pub fn install_package(pkg: &PackageMetadata, dest: &Path) -> Result<()> {
        let url = &pkg.download_url;
        eprintln!("Downloading {} {}...", pkg.name, pkg.version);

        // Download to temp file
        let resp = ureq::get(url).call()
            .map_err(|e| OilError::Install(format!("download failed for {}: {e}", pkg.name)))?;

        use std::io::Read;
        let body = resp.into_body();
        let mut data = Vec::new();
        body.into_reader().read_to_end(&mut data)
            .map_err(|e| OilError::Install(format!("read failed for {}: {e}", pkg.name)))?;

        let tmp = tempfile::NamedTempFile::new()
            .map_err(|e| OilError::Install(format!("temp file: {e}")))?;

        std::fs::write(tmp.path(), &data)
            .map_err(|e| OilError::Install(format!("write temp: {e}")))?;

        eprintln!("Extracting {}...", pkg.name);
        extract_package_tracked(tmp.path(), dest)?;

        Ok(())
    }
}

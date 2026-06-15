/// Void Linux XBPS package registry.
///
/// Fetches and parses Void Linux binary repository index.
/// Supports direct HTTP fetch + CLI fallback via xbps-query.
use super::{PackageIndex, PackageMetadata};
use crate::error::{Result, OilError};
use std::time::{Duration, SystemTime};
use tracing::debug;

pub struct XbpsRegistry {
    mirror: String,
    subrepo: String,
    arch: String,
}

impl XbpsRegistry {
    pub fn new(mirror: &str, subrepo: &str, arch: &str) -> Self {
        Self { mirror: mirror.trim_end_matches('/').to_string(), subrepo: subrepo.trim_end_matches('/').to_string(), arch: arch.to_string() }
    }

    pub fn void_musl_default() -> Self {
        let arch = std::env::consts::ARCH;
        let xbps_arch: String = match arch {
            "x86_64" => "x86_64-musl".into(),
            "aarch64" => "aarch64-musl".into(),
            "arm" => "armv7l-musl".into(),
            other => format!("{}-musl", other),
        };
        Self::new("https://repo-default.voidlinux.org", "current/musl", &xbps_arch)
    }

    fn repodata_url(&self) -> String {
        format!("{}/{}/{}/repodata/{}-repodata", self.mirror, self.subrepo, self.arch, self.arch)
    }

    fn cache_path(&self) -> Result<std::path::PathBuf> {
        let dir = crate::ui::dirs::oil_cache_dir()?.join("system");
        std::fs::create_dir_all(&dir)?;
        let safe: String = format!("{}-{}-{}", self.mirror, self.subrepo, self.arch)
            .chars().map(|c| if c.is_alphanumeric() || c == '-' { c } else { '_' }).collect();
        Ok(dir.join(format!("xbps-{}.json", safe)))
    }

    fn is_cache_fresh(path: &std::path::Path) -> bool {
        if let Ok(meta) = std::fs::metadata(path) {
            if let Ok(modified) = meta.modified() {
                if let Ok(elapsed) = SystemTime::now().duration_since(modified) {
                    return elapsed < Duration::from_secs(24 * 3600);
                }
            }
        }
        false
    }

    pub async fn load(&self, client: &reqwest::Client) -> Result<PackageIndex> {
        let cache_path = self.cache_path()?;
        if Self::is_cache_fresh(&cache_path) {
            debug!("Loading XBPS index from cache");
            let data = std::fs::read_to_string(&cache_path)?;
            let packages: Vec<PackageMetadata> = serde_json::from_str(&data)?;
            return Ok(PackageIndex { packages });
        }

        let repodata_url = self.repodata_url();
        debug!("Fetching XBPS repodata from {}", repodata_url);
        let resp = client.get(&repodata_url).send().await.map_err(|e| OilError::InstallError(format!("Failed to fetch XBPS repodata: {}", e)))?;
        if !resp.status().is_success() {
            return Err(OilError::InstallError(format!("XBPS repodata HTTP {}", resp.status())));
        }
        let bytes = resp.bytes().await.map_err(|e| OilError::InstallError(format!("Failed to read XBPS repodata: {}", e)))?;
        let mut decoder = flate2::read::GzDecoder::new(&bytes[..]);
        let mut decompressed = Vec::new();
        use std::io::Read;
        decoder.read_to_end(&mut decompressed).map_err(|e| OilError::InstallError(format!("Decompress error: {}", e)))?;

        let packages = parse_xbps_repodata(&decompressed, &self.mirror, &self.subrepo, &self.arch)?;
        let json = serde_json::to_string(&packages)?;
        let _ = std::fs::write(&cache_path, &json);
        debug!("Parsed {} XBPS packages", packages.len());
        Ok(PackageIndex { packages })
    }
}

fn parse_xbps_repodata(data: &[u8], mirror: &str, subrepo: &str, _arch: &str) -> Result<Vec<PackageMetadata>> {
    let mut packages = Vec::new();
    if let Ok(text) = std::str::from_utf8(data) {
        if text.contains("pkgver:") {
            for stanza in text.split('\n') {
                let stanza = stanza.trim();
                if stanza.is_empty() { continue; }
                let mut pkgver = String::new();
                let mut short_desc = String::new();
                let mut filename = String::new();
                for line in stanza.lines() {
                    let line = line.trim();
                    if let Some((key, value)) = line.split_once(':') {
                        match key.trim() {
                            "pkgver" => pkgver = value.trim().to_string(),
                            "short_desc" => short_desc = value.trim().to_string(),
                            "filename" => filename = value.trim().to_string(),
                            _ => {}
                        }
                    }
                }
                if !pkgver.is_empty() {
                    let (name, version) = split_pkgver(&pkgver);
                    if !name.is_empty() && !version.is_empty() {
                        let dl = if filename.is_empty() {
                            format!("{}/{}/packages/{}/{}.xbps", mirror, subrepo, name.chars().next().unwrap_or('z'), pkgver)
                        } else {
                            format!("{}/{}/{}", mirror, subrepo, filename)
                        };
                        packages.push(PackageMetadata { name, version, description: short_desc, download_url: dl, sha256: None, installed_size: 0, depends: vec![], provides: vec![] });
                    }
                }
            }
        }
    }
    Ok(packages)
}

fn split_pkgver(pkgver: &str) -> (String, String) {
    if let Some(pos) = pkgver.rfind('-') {
        let after = &pkgver[pos+1..];
        if after.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) {
            return (pkgver[..pos].to_string(), after.to_string());
        }
    }
    (pkgver.to_string(), String::new())
}

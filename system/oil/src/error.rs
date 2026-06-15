use std::fmt;

#[derive(Debug)]
pub enum OilError {
    Http(String),
    Json(serde_json::Error),
    Io(std::io::Error),
    FormulaNotFound(String),
    Cache(String),
    ChecksumMismatch { expected: String, actual: String },
    Install(String),
    NotInstalled(String),
    Lockfile(String),
    InvalidInput(String),
    PlatformNotSupported(String),
    Parse(String),
    DependencyCycle(String),
    Interrupted,
}

impl fmt::Display for OilError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OilError::Http(msg) => write!(f, "HTTP error: {msg}"),
            OilError::Json(e) => write!(f, "JSON error: {e}"),
            OilError::Io(e) => write!(f, "I/O error: {e}"),
            OilError::FormulaNotFound(name) => write!(f, "formula not found: {name}"),
            OilError::Cache(msg) => write!(f, "cache error: {msg}"),
            OilError::ChecksumMismatch { expected, actual } => {
                write!(f, "checksum mismatch: expected {expected}, got {actual}")
            }
            OilError::Install(msg) => write!(f, "installation failed: {msg}"),
            OilError::NotInstalled(name) => write!(f, "package not installed: {name}"),
            OilError::Lockfile(msg) => write!(f, "lockfile error: {msg}"),
            OilError::InvalidInput(msg) => write!(f, "invalid input: {msg}"),
            OilError::PlatformNotSupported(msg) => write!(f, "{msg}"),
            OilError::Parse(msg) => write!(f, "parse error: {msg}"),
            OilError::DependencyCycle(msg) => write!(f, "dependency cycle: {msg}"),
            OilError::Interrupted => write!(f, "interrupted"),
        }
    }
}

impl std::error::Error for OilError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            OilError::Json(e) => Some(e),
            OilError::Io(e) => Some(e),
            _ => None,
        }
    }
}

impl From<serde_json::Error> for OilError {
    fn from(e: serde_json::Error) -> Self {
        OilError::Json(e)
    }
}

impl From<std::io::Error> for OilError {
    fn from(e: std::io::Error) -> Self {
        OilError::Io(e)
    }
}

impl From<ureq::Error> for OilError {
    fn from(e: ureq::Error) -> Self {
        OilError::Http(e.to_string())
    }
}

pub type Result<T> = std::result::Result<T, OilError>;

pub fn validate_package_name(name: &str) -> Result<()> {
    if name.is_empty() {
        return Err(OilError::InvalidInput(
            "Package name cannot be empty".to_string(),
        ));
    }
    if name.starts_with('/') || name.ends_with('/') {
        return Err(OilError::InvalidInput(format!(
            "Package name must not start or end with '/': {name}"
        )));
    }
    for segment in name.split('/') {
        if segment.is_empty() {
            return Err(OilError::InvalidInput(format!(
                "Package name contains empty path segment: {name}"
            )));
        }
        if segment == "." || segment == ".." {
            return Err(OilError::InvalidInput(format!(
                "Package name contains invalid path segment '{segment}': {name}"
            )));
        }
    }
    if name.contains("..") {
        return Err(OilError::InvalidInput(format!(
            "Package name contains path traversal: {name}"
        )));
    }
    if !name
        .chars()
        .all(|c| c.is_alphanumeric() || "-_.+@/".contains(c))
    {
        return Err(OilError::InvalidInput(format!(
            "Package name contains invalid characters: {name}"
        )));
    }
    Ok(())
}

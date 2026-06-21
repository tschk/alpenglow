use std::fmt;

#[derive(Debug)]
pub enum OilError {
    Http(String),
    Json(serde_json::Error),
    Io(std::io::Error),
    FormulaNotFound(String),
    ChecksumMismatch { expected: String, actual: String },
    Install(String),
}

impl fmt::Display for OilError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OilError::Http(msg) => write!(f, "HTTP error: {msg}"),
            OilError::Json(e) => write!(f, "JSON error: {e}"),
            OilError::Io(e) => write!(f, "I/O error: {e}"),
            OilError::FormulaNotFound(name) => write!(f, "formula not found: {name}"),
            OilError::ChecksumMismatch { expected, actual } => {
                write!(f, "checksum mismatch: expected {expected}, got {actual}")
            }
            OilError::Install(msg) => write!(f, "{msg}"),
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

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

#[cfg(test)]
mod tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn test_display() {
        assert_eq!(
            OilError::Http("404 Not Found".to_string()).to_string(),
            "HTTP error: 404 Not Found"
        );
        assert_eq!(
            OilError::FormulaNotFound("curl".to_string()).to_string(),
            "formula not found: curl"
        );
        assert_eq!(
            OilError::ChecksumMismatch {
                expected: "abc".to_string(),
                actual: "def".to_string()
            }
            .to_string(),
            "checksum mismatch: expected abc, got def"
        );
        assert_eq!(
            OilError::Install("install failed".to_string()).to_string(),
            "install failed"
        );
    }

    #[test]
    fn test_from_and_source() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let oil_io: OilError = io_err.into();
        assert!(oil_io.to_string().starts_with("I/O error:"));
        assert!(oil_io.source().is_some());

        let json_err = serde_json::from_str::<serde_json::Value>("{ invalid").unwrap_err();
        let oil_json: OilError = json_err.into();
        assert!(oil_json.to_string().starts_with("JSON error:"));
        assert!(oil_json.source().is_some());

        let http_err = ureq::get("invalid://url").call().unwrap_err();
        let oil_http: OilError = http_err.into();
        assert!(oil_http.to_string().starts_with("HTTP error:"));
        // Http variants don't provide a source
        assert!(oil_http.source().is_none());

        let install_err = OilError::Install("msg".to_string());
        assert!(install_err.source().is_none());
    }
}

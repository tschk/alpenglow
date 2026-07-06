use std::fmt;

#[derive(Debug)]
pub enum OilError {
    Http(String),
    Json(serde_json::Error),
    Io(std::io::Error),
    FormulaNotFound(String),
    ChecksumMismatch { expected: String, actual: String },
    Install(String),
    Recipe(String),
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
            OilError::Recipe(msg) => write!(f, "recipe error: {msg}"),
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

impl From<serde_norway::Error> for OilError {
    fn from(e: serde_norway::Error) -> Self {
        OilError::Recipe(e.to_string())
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
    fn test_display_http() {
        let err = OilError::Http("Connection reset".to_string());
        assert_eq!(err.to_string(), "HTTP error: Connection reset");
    }

    #[test]
    fn test_display_json() {
        // We can create a serde_json::Error by attempting to parse invalid JSON.
        let serde_err: std::result::Result<serde_json::Value, serde_json::Error> =
            serde_json::from_str("{ invalid }");
        let json_err = serde_err.unwrap_err();
        let expected_msg = format!("JSON error: {json_err}");
        let err = OilError::Json(json_err);
        assert_eq!(err.to_string(), expected_msg);
    }

    #[test]
    fn test_display_io() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let expected_msg = format!("I/O error: {io_err}");
        let err = OilError::Io(io_err);
        assert_eq!(err.to_string(), expected_msg);
    }

    #[test]
    fn test_display_formula_not_found() {
        let err = OilError::FormulaNotFound("curl".to_string());
        assert_eq!(err.to_string(), "formula not found: curl");
    }

    #[test]
    fn test_display_checksum_mismatch() {
        let err = OilError::ChecksumMismatch {
            expected: "abcdef".to_string(),
            actual: "123456".to_string(),
        };
        assert_eq!(
            err.to_string(),
            "checksum mismatch: expected abcdef, got 123456"
        );
    }

    #[test]
    fn test_display_install() {
        let err = OilError::Install("Failed to create directory".to_string());
        assert_eq!(err.to_string(), "Failed to create directory");
    }

    #[test]
    fn test_source() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let err_io = OilError::Io(io_err);
        assert!(err_io.source().is_some());

        let serde_err: std::result::Result<serde_json::Value, serde_json::Error> =
            serde_json::from_str("{ invalid }");
        let json_err = serde_err.unwrap_err();
        let err_json = OilError::Json(json_err);
        assert!(err_json.source().is_some());

        let err_http = OilError::Http("Connection reset".to_string());
        assert!(err_http.source().is_none());
    }

    #[test]
    fn test_from_serde_json_error() {
        let serde_err: std::result::Result<serde_json::Value, serde_json::Error> =
            serde_json::from_str("{ invalid }");
        let orig_err = serde_err.unwrap_err();
        let err_msg = orig_err.to_string();

        let err: OilError = orig_err.into();
        match err {
            OilError::Json(e) => assert_eq!(e.to_string(), err_msg),
            _ => panic!("Expected OilError::Json"),
        }
    }

    #[test]
    fn test_from_io_error() {
        let orig_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let err_msg = orig_err.to_string();

        let err: OilError = orig_err.into();
        match err {
            OilError::Io(e) => assert_eq!(e.to_string(), err_msg),
            _ => panic!("Expected OilError::Io"),
        }
    }

    #[test]
    fn test_from_ureq_error() {
        // ureq::Error doesn't easily let us construct all variants, but we can use an invalid URL
        // We construct a std::io::Error and convert it into a ureq::Error.
        let io_err = std::io::Error::new(std::io::ErrorKind::Other, "mock transport error");
        let ureq_err: ureq::Error = io_err.into();
        let err_msg = ureq_err.to_string();

        let err: OilError = ureq_err.into();
        match err {
            OilError::Http(msg) => assert_eq!(msg, err_msg),
            _ => panic!("Expected OilError::Http"),
        }
    }
}

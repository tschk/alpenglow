use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufReader, BufWriter};
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub enum InstallError {
    Io(io::Error),
    InvalidTarget(String),
}

impl fmt::Display for InstallError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            InstallError::Io(err) => write!(f, "{err}"),
            InstallError::InvalidTarget(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for InstallError {}

impl From<io::Error> for InstallError {
    fn from(err: io::Error) -> Self {
        InstallError::Io(err)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallRequest {
    pub source: PathBuf,
    pub target: PathBuf,
    pub allow_regular_file: bool,
}

pub fn validate_target(target: &Path, allow_regular_file: bool) -> Result<(), InstallError> {
    if allow_regular_file && !target.exists() {
        return Ok(());
    }
    let metadata = fs::metadata(target)?;
    if metadata.is_file() && allow_regular_file {
        return Ok(());
    }
    if is_block_device(&metadata) {
        return Ok(());
    }
    Err(InstallError::InvalidTarget(format!(
        "refusing to write image to non-block-device target: {}",
        target.display()
    )))
}

pub fn install_image(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
) -> Result<u64, InstallError> {
    validate_target(target, allow_regular_file)?;
    let input = File::open(source)?;
    let output = OpenOptions::new()
        .write(true)
        .create(allow_regular_file)
        .truncate(allow_regular_file)
        .open(target)?;
    let mut input = BufReader::new(input);
    let mut output = BufWriter::new(output);
    Ok(io::copy(&mut input, &mut output)?)
}

#[cfg(unix)]
fn is_block_device(metadata: &fs::Metadata) -> bool {
    use std::os::unix::fs::FileTypeExt;
    metadata.file_type().is_block_device()
}

#[cfg(not(unix))]
fn is_block_device(_metadata: &fs::Metadata) -> bool {
    false
}

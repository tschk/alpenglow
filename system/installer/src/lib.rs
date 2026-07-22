mod tui;

use std::ffi::OsString;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufReader, BufWriter};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

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

pub fn default_live_source() -> PathBuf {
    PathBuf::from("/run/alpenglow/alpenglow.img.zst")
}

pub fn parse_install_args<I, T>(args: I) -> (PathBuf, Option<PathBuf>)
where
    I: IntoIterator<Item = T>,
    T: Into<PathBuf>,
{
    let mut args = args.into_iter();
    let source = args
        .next()
        .map(Into::into)
        .unwrap_or_else(default_live_source);
    let target = args.next().map(Into::into);
    (source, target)
}

/// Parses installer argv: optional `--tui`, then optional source and target paths.
pub fn parse_installer_args<I>(args: I) -> (bool, PathBuf, Option<PathBuf>)
where
    I: IntoIterator<Item = OsString>,
{
    let mut tui = false;
    let mut positionals = Vec::new();
    for arg in args {
        if arg == "--tui" {
            tui = true;
        } else {
            positionals.push(arg);
        }
    }
    let (source, target) = parse_install_args(positionals);
    (tui, source, target)
}

/// Shared entry for `alpenglow-install` and the `alpenglow-install-tui` wrapper.
pub fn run_installer<I>(args: I) -> i32
where
    I: IntoIterator<Item = OsString>,
{
    let (tui, source, target) = parse_installer_args(args);
    if tui {
        if let Err(err) = tui::draw_installer_tui(&source, target.as_deref()) {
            eprintln!("installer ui failed: {err}");
            return 1;
        }
    }
    let Some(target) = target else {
        eprintln!("usage: alpenglow-install [--tui] <source.img|source.img.zst> <target-disk>");
        return 2;
    };
    match install_image_maybe_compressed(&source, &target, false) {
        Ok(bytes) => {
            println!("wrote {bytes} bytes to {}", target.display());
            0
        }
        Err(err) => {
            eprintln!("install failed: {err}");
            1
        }
    }
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

pub fn install_image_maybe_compressed(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
) -> Result<u64, InstallError> {
    if source.extension().and_then(|ext| ext.to_str()) != Some("zst") {
        return install_image(source, target, allow_regular_file);
    }
    validate_target(target, allow_regular_file)?;
    let mut child = Command::new("zstd")
        .arg("-dc")
        .arg("--")
        .arg(source)
        .stdout(Stdio::piped())
        .spawn()?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| InstallError::InvalidTarget("zstd stdout unavailable".to_string()))?;
    let output = OpenOptions::new()
        .write(true)
        .create(allow_regular_file)
        .truncate(allow_regular_file)
        .open(target)?;
    let mut input = BufReader::new(stdout);
    let mut output = BufWriter::new(output);
    let bytes = io::copy(&mut input, &mut output)?;
    let status = child.wait()?;
    if !status.success() {
        return Err(InstallError::InvalidTarget(format!(
            "zstd failed for {}",
            source.display()
        )));
    }
    Ok(bytes)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_install_args_zero_args() {
        let args: Vec<&str> = vec![];
        let (source, target) = parse_install_args(args);
        assert_eq!(source, default_live_source());
        assert_eq!(target, None);
    }

    #[test]
    fn test_parse_install_args_one_arg() {
        let args = vec!["custom_source.img"];
        let (source, target) = parse_install_args(args);
        assert_eq!(source, PathBuf::from("custom_source.img"));
        assert_eq!(target, None);
    }

    #[test]
    fn test_parse_install_args_two_args() {
        let args = vec!["custom_source.img", "/dev/nvme0n1"];
        let (source, target) = parse_install_args(args);
        assert_eq!(source, PathBuf::from("custom_source.img"));
        assert_eq!(target, Some(PathBuf::from("/dev/nvme0n1")));
    }

    #[test]
    fn test_parse_install_args_three_args() {
        let args = vec!["custom_source.img", "/dev/nvme0n1", "extra_arg"];
        let (source, target) = parse_install_args(args);
        assert_eq!(source, PathBuf::from("custom_source.img"));
        assert_eq!(target, Some(PathBuf::from("/dev/nvme0n1")));
    }
}

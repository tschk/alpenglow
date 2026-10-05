pub mod inuse;
mod tui;
pub mod wizard;

use std::ffi::OsString;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufReader, BufWriter, Read, Seek, SeekFrom, Write};
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

/// Shared installer entry (`alpenglow-install --tui` enables the TUI).
pub fn run_installer<I>(args: I) -> i32
where
    I: IntoIterator<Item = OsString>,
{
    run_installer_with_draw(args, tui::draw_installer_tui)
}

pub fn run_installer_with_draw<I, F>(args: I, draw: F) -> i32
where
    I: IntoIterator<Item = OsString>,
    F: FnOnce(&Path, Option<&Path>) -> Result<(), String>,
{
    let (tui, source, target) = parse_installer_args(args);
    if tui {
        if let Err(err) = draw(&source, target.as_deref()) {
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

/// Bytes written so far and, when known, the expected total (plain image size, or the
/// decompressed size recorded in a zstd frame header).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InstallProgress {
    pub written: u64,
    pub total: Option<u64>,
}

impl InstallProgress {
    /// Whole percent complete, clamped to 100; `None` when the total is unknown.
    pub fn percent(&self) -> Option<u8> {
        let total = self.total.filter(|total| *total > 0)?;
        Some((self.written.min(total).saturating_mul(100) / total) as u8)
    }
}

const COPY_BUFFER: usize = 1 << 20;
const PROGRESS_STEP: u64 = 4 << 20;

/// Decompressed size of a zstd file when its first frame header records it.
fn zstd_content_size(file: &mut File) -> io::Result<Option<u64>> {
    let mut header = [0u8; 18];
    let read = file.read(&mut header)?;
    file.seek(SeekFrom::Start(0))?;
    Ok(zstd::zstd_safe::get_frame_content_size(&header[..read])
        .ok()
        .flatten())
}

fn is_zstd_path(source: &Path) -> bool {
    source.extension().and_then(|ext| ext.to_str()) == Some("zst")
}

/// Copies `source` onto `target`, decompressing a `.zst` source, and reports progress. Flushes
/// and syncs so a successful return means the data reached the device.
pub fn install_image_with_progress<F>(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
    on_progress: F,
) -> Result<u64, InstallError>
where
    F: FnMut(InstallProgress),
{
    copy_image(
        source,
        target,
        allow_regular_file,
        is_zstd_path(source),
        on_progress,
    )
}

fn copy_image<F>(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
    compressed: bool,
    mut on_progress: F,
) -> Result<u64, InstallError>
where
    F: FnMut(InstallProgress),
{
    validate_target(target, allow_regular_file)?;
    let mut input_file = File::open(source)?;
    let total = if compressed {
        zstd_content_size(&mut input_file)?
    } else {
        Some(input_file.metadata()?.len())
    };
    let mut input: Box<dyn Read> = if compressed {
        Box::new(BufReader::new(zstd::stream::Decoder::new(input_file)?))
    } else {
        Box::new(BufReader::new(input_file))
    };
    let output = OpenOptions::new()
        .write(true)
        .create(allow_regular_file)
        .truncate(allow_regular_file)
        .open(target)?;
    let mut writer = BufWriter::new(output);

    let mut buffer = vec![0u8; COPY_BUFFER];
    let mut written = 0u64;
    let mut reported = 0u64;
    on_progress(InstallProgress { written, total });
    loop {
        let read = input.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        writer.write_all(&buffer[..read])?;
        written += read as u64;
        if written - reported >= PROGRESS_STEP {
            reported = written;
            on_progress(InstallProgress { written, total });
        }
    }
    writer.flush()?;
    writer.get_ref().sync_all()?;
    on_progress(InstallProgress { written, total });
    Ok(written)
}

pub fn install_image(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
) -> Result<u64, InstallError> {
    copy_image(source, target, allow_regular_file, false, |_| {})
}

pub fn install_image_maybe_compressed(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
) -> Result<u64, InstallError> {
    install_image_with_progress(source, target, allow_regular_file, |_| {})
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
    use tempfile::{tempdir, NamedTempFile};

    #[test]
    fn test_default_live_source() {
        assert_eq!(
            default_live_source(),
            PathBuf::from("/run/alpenglow/alpenglow.img.zst")
        );
    }

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

    #[test]
    fn test_validate_target_new_file_allowed() {
        let dir = tempdir().unwrap();
        let target = dir.path().join("new_file.img");

        let result = validate_target(&target, true);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_target_existing_file_allowed() {
        let file = NamedTempFile::new().unwrap();
        let target = file.path();

        let result = validate_target(target, true);
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_target_existing_file_not_allowed() {
        let file = NamedTempFile::new().unwrap();
        let target = file.path();

        let result = validate_target(target, false);
        assert!(result.is_err());
        match result {
            Err(InstallError::InvalidTarget(msg)) => {
                assert!(msg.contains("refusing to write image to non-block-device target"));
            }
            _ => panic!("Expected InvalidTarget error"),
        }
    }

    #[test]
    fn test_validate_target_not_found_not_allowed() {
        let dir = tempdir().unwrap();
        let target = dir.path().join("non_existent.img");

        let result = validate_target(&target, false);
        assert!(result.is_err());
        match result {
            Err(InstallError::Io(err)) => {
                assert_eq!(err.kind(), io::ErrorKind::NotFound);
            }
            _ => panic!("Expected Io error"),
        }
    }

    #[test]
    fn test_parse_installer_args_empty() {
        let args: Vec<OsString> = vec![];
        let (tui, source, target) = parse_installer_args(args);
        assert_eq!(tui, false);
        assert_eq!(source, default_live_source());
        assert_eq!(target, None);
    }

    #[test]
    fn test_parse_installer_args_tui_only() {
        let args: Vec<OsString> = vec![OsString::from("--tui")];
        let (tui, source, target) = parse_installer_args(args);
        assert_eq!(tui, true);
        assert_eq!(source, default_live_source());
        assert_eq!(target, None);
    }

    #[test]
    fn test_parse_installer_args_source_only() {
        let args: Vec<OsString> = vec![OsString::from("source.img")];
        let (tui, source, target) = parse_installer_args(args);
        assert_eq!(tui, false);
        assert_eq!(source, PathBuf::from("source.img"));
        assert_eq!(target, None);
    }

    #[test]
    fn test_parse_installer_args_tui_and_source() {
        let args: Vec<OsString> = vec![OsString::from("--tui"), OsString::from("source.img")];
        let (tui, source, target) = parse_installer_args(args);
        assert_eq!(tui, true);
        assert_eq!(source, PathBuf::from("source.img"));
        assert_eq!(target, None);
    }

    #[test]
    fn test_parse_installer_args_tui_source_target() {
        let args: Vec<OsString> = vec![
            OsString::from("--tui"),
            OsString::from("source.img"),
            OsString::from("/dev/sda"),
        ];
        let (tui, source, target) = parse_installer_args(args);
        assert_eq!(tui, true);
        assert_eq!(source, PathBuf::from("source.img"));
        assert_eq!(target, Some(PathBuf::from("/dev/sda")));
    }

    #[test]
    fn test_parse_installer_args_source_tui_target() {
        let args: Vec<OsString> = vec![
            OsString::from("source.img"),
            OsString::from("--tui"),
            OsString::from("/dev/sda"),
        ];
        let (tui, source, target) = parse_installer_args(args);
        assert_eq!(tui, true);
        assert_eq!(source, PathBuf::from("source.img"));
        assert_eq!(target, Some(PathBuf::from("/dev/sda")));
    }

    #[test]
    fn test_run_installer_no_args() {
        let args: Vec<OsString> = vec![];
        assert_eq!(run_installer(args), 2);
    }

    #[test]
    fn test_run_installer_tui_no_target() {
        fn fake_draw(_source: &Path, _target: Option<&Path>) -> Result<(), String> {
            Ok(())
        }
        let args: Vec<OsString> = vec![OsString::from("--tui")];
        assert_eq!(run_installer_with_draw(args, fake_draw), 2);
    }

    #[test]
    fn test_run_installer_fail_invalid_target() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.img");
        std::fs::write(&source, b"testdata").unwrap();

        let args: Vec<OsString> = vec![
            OsString::from(source.to_string_lossy().to_string()),
            OsString::from("/dev/null_does_not_exist_xyz"),
        ];
        assert_eq!(run_installer(args), 1);
    }
}

mod tui;

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
    run_installer_with_draw_and_install(
        args,
        tui::draw_installer_tui,
        install_image_maybe_compressed,
    )
}

pub fn run_installer_with_draw<I, F>(args: I, draw: F) -> i32
where
    I: IntoIterator<Item = OsString>,
    F: FnOnce(&Path, Option<&Path>) -> Result<(), String>,
{
    run_installer_with_draw_and_install(args, draw, install_image_maybe_compressed)
}

pub fn run_installer_with_draw_and_install<I, F, G>(args: I, draw: F, install: G) -> i32
where
    I: IntoIterator<Item = OsString>,
    F: FnOnce(&Path, Option<&Path>) -> Result<(), String>,
    G: FnOnce(&Path, &Path, bool) -> Result<u64, InstallError>,
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
    match install(&source, &target, false) {
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
    target_metadata(target, allow_regular_file).map(|_| ())
}

fn target_metadata(
    target: &Path,
    allow_regular_file: bool,
) -> Result<Option<fs::Metadata>, InstallError> {
    if allow_regular_file && !target.exists() {
        return Ok(None);
    }
    let metadata = fs::metadata(target)?;
    if metadata.is_file() && allow_regular_file {
        return Ok(Some(metadata));
    }
    if is_block_device(&metadata) {
        return Ok(Some(metadata));
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
    install_image_inner(source, target, allow_regular_file, false)
}

pub fn install_image_maybe_compressed(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
) -> Result<u64, InstallError> {
    let compressed = source.extension().and_then(|ext| ext.to_str()) == Some("zst");
    install_image_inner(source, target, allow_regular_file, compressed)
}

fn install_image_inner(
    source: &Path,
    target: &Path,
    allow_regular_file: bool,
    compressed: bool,
) -> Result<u64, InstallError> {
    let target_metadata = target_metadata(target, allow_regular_file)?;
    let mut input = File::open(source)?;
    let source_metadata = input.metadata()?;
    if !source_metadata.is_file() {
        return Err(InstallError::Io(io::Error::new(
            io::ErrorKind::InvalidInput,
            "source must be a regular image file",
        )));
    }
    let is_block = target_metadata.as_ref().is_some_and(is_block_device);
    let mut options = OpenOptions::new();
    options.write(true);
    if target_metadata.is_none() && allow_regular_file {
        options.create_new(true);
    }
    #[cfg(target_os = "linux")]
    if is_block || !allow_regular_file {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_EXCL);
    }
    #[cfg(not(target_os = "linux"))]
    if is_block {
        return Err(InstallError::InvalidTarget(
            "block device safety requires Linux".into(),
        ));
    }
    let mut output = options.open(target)?;
    let output_metadata = output.metadata()?;
    if is_block_device(&output_metadata) != is_block
        || (!is_block && !(allow_regular_file && output_metadata.is_file()))
    {
        return Err(InstallError::InvalidTarget(
            "target changed during validation".into(),
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if let Some(expected) = &target_metadata {
            if (expected.dev(), expected.ino(), expected.rdev())
                != (
                    output_metadata.dev(),
                    output_metadata.ino(),
                    output_metadata.rdev(),
                )
            {
                return Err(InstallError::InvalidTarget(
                    "target changed during validation".into(),
                ));
            }
        }
        if (source_metadata.dev(), source_metadata.ino())
            == (output_metadata.dev(), output_metadata.ino())
        {
            return Err(InstallError::InvalidTarget(
                "source and target are the same file or device".into(),
            ));
        }
    }
    let image_size = if is_block {
        let capacity = output.seek(SeekFrom::End(0))?;
        output.seek(SeekFrom::Start(0))?;
        let image_size = if compressed {
            io::copy(
                &mut zstd::stream::Decoder::new(&mut input)?,
                &mut io::sink(),
            )?
        } else {
            input.seek(SeekFrom::End(0))?
        };
        input.seek(SeekFrom::Start(0))?;
        if image_size > capacity {
            return Err(InstallError::InvalidTarget(format!(
                "image requires {image_size} bytes but target has {capacity} bytes"
            )));
        }
        Some(image_size)
    } else {
        output.set_len(0)?;
        None
    };
    let mut output = BufWriter::new(output);
    let mut input: Box<dyn Read> = if compressed {
        Box::new(BufReader::new(zstd::stream::Decoder::new(input)?))
    } else {
        Box::new(BufReader::new(input))
    };
    let bytes = if let Some(expected) = image_size {
        let copied = io::copy(&mut input.by_ref().take(expected), &mut output)?;
        let mut extra = [0u8; 1];
        if copied != expected || input.read(&mut extra)? != 0 {
            return Err(InstallError::Io(io::Error::other(
                "source image changed during installation",
            )));
        }
        copied
    } else {
        io::copy(&mut input, &mut output)?
    };
    output.flush()?;
    output.get_ref().sync_all()?;
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

    #[test]
    fn test_run_installer_success_with_mock() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.img");
        let target = dir.path().join("target.img");

        let args: Vec<OsString> = vec![
            OsString::from(source.to_string_lossy().to_string()),
            OsString::from(target.to_string_lossy().to_string()),
        ];

        fn fake_draw(_source: &Path, _target: Option<&Path>) -> Result<(), String> {
            Ok(())
        }

        fn fake_install(
            _source: &Path,
            _target: &Path,
            allow_regular: bool,
        ) -> Result<u64, InstallError> {
            // The CLI must never permit installing onto a regular file.
            assert!(!allow_regular);
            Ok(42)
        }

        assert_eq!(
            run_installer_with_draw_and_install(args, fake_draw, fake_install),
            0
        );
    }

    #[test]
    fn test_run_installer_install_fail_with_mock() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.img");
        let target = dir.path().join("target.img");

        let args: Vec<OsString> = vec![
            OsString::from(source.to_string_lossy().to_string()),
            OsString::from(target.to_string_lossy().to_string()),
        ];

        fn fake_draw(_source: &Path, _target: Option<&Path>) -> Result<(), String> {
            Ok(())
        }

        fn fake_install(
            _source: &Path,
            _target: &Path,
            _allow_regular: bool,
        ) -> Result<u64, InstallError> {
            Err(InstallError::Io(std::io::Error::other("mock error")))
        }

        assert_eq!(
            run_installer_with_draw_and_install(args, fake_draw, fake_install),
            1
        );
    }

    #[test]
    fn test_run_installer_tui_fail_with_mock() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.img");
        let target = dir.path().join("target.img");

        let args: Vec<OsString> = vec![
            OsString::from("--tui"),
            OsString::from(source.to_string_lossy().to_string()),
            OsString::from(target.to_string_lossy().to_string()),
        ];

        fn fake_draw_fail(_source: &Path, _target: Option<&Path>) -> Result<(), String> {
            Err("mock tui error".to_string())
        }

        fn fake_install_unreachable(
            _source: &Path,
            _target: &Path,
            _allow_regular: bool,
        ) -> Result<u64, InstallError> {
            unreachable!("install should not be called if tui fails")
        }

        assert_eq!(
            run_installer_with_draw_and_install(args, fake_draw_fail, fake_install_unreachable),
            1
        );
    }
}

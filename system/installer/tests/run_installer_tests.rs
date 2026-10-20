use alpenglow_installer::{run_installer_internal, run_installer_with_draw};
use std::ffi::OsString;
use std::fs;
use std::path::Path;

#[test]
fn test_run_installer_success_with_regular_file() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    fs::write(&source, b"test_image_data").unwrap();

    let target = dir.path().join("target.img");

    let args: Vec<OsString> = vec![
        OsString::from(source.to_str().unwrap()),
        OsString::from(target.to_str().unwrap()),
    ];

    let draw = |_: &Path, _: Option<&Path>| Ok(());

    // By passing true for allow_regular_file we can fully test the installer flow
    // without needing actual block devices.
    let result = run_installer_internal(args, draw, true);
    assert_eq!(result, 0);

    assert_eq!(fs::read(&target).unwrap(), b"test_image_data");
}

#[test]
fn test_run_installer_with_draw_passes_false() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    fs::write(&source, b"test_image_data").unwrap();

    let target = dir.path().join("target.img");

    let args: Vec<OsString> = vec![
        OsString::from(source.to_str().unwrap()),
        OsString::from(target.to_str().unwrap()),
    ];

    let draw = |_: &Path, _: Option<&Path>| Ok(());

    // Should fail because allow_regular_file is false, so it refuses to write to a non-block device.
    let result = run_installer_with_draw(args, draw);
    assert_eq!(result, 1);
}

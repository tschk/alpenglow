use alpenglow_installer::{
    default_live_source, install_image, install_image_maybe_compressed, parse_install_args,
    parse_installer_args, validate_target,
};
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;

#[test]
fn rejects_non_device_targets_by_default() {
    let dir = tempfile::tempdir().unwrap();
    let target = dir.path().join("disk.img");
    fs::write(&target, []).unwrap();
    let err = validate_target(&target, false).unwrap_err();
    assert!(err.to_string().contains("refusing"));
}

#[test]
fn copies_image_when_allowed() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    let target = dir.path().join("target.img");
    fs::write(&source, b"alpenglow").unwrap();
    install_image(&source, &target, true).unwrap();
    assert_eq!(fs::read(&target).unwrap(), b"alpenglow");
}

#[test]
fn plain_auto_install_copies_image_when_allowed() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    let target = dir.path().join("target.img");
    fs::write(&source, b"alpenglow").unwrap();
    install_image_maybe_compressed(&source, &target, true).unwrap();
    assert_eq!(fs::read(&target).unwrap(), b"alpenglow");
}

#[test]
fn zst_auto_install_decompresses_image_when_allowed() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img.zst");
    let target = dir.path().join("target.img");

    // Valid zstd compressed payload for "alpenglow-compressed-test"
    let zst_data: &[u8] = &[
        0x28, 0xb5, 0x2f, 0xfd, 0x04, 0x58, 0xc9, 0x00, 0x00, 0x61, 0x6c, 0x70,
        0x65, 0x6e, 0x67, 0x6c, 0x6f, 0x77, 0x2d, 0x63, 0x6f, 0x6d, 0x70, 0x72,
        0x65, 0x73, 0x73, 0x65, 0x64, 0x2d, 0x74, 0x65, 0x73, 0x74, 0xc6, 0x62,
        0xe6, 0x26
    ];
    fs::write(&source, zst_data).unwrap();

    install_image_maybe_compressed(&source, &target, true).unwrap();
    assert_eq!(fs::read(&target).unwrap(), b"alpenglow-compressed-test");
}

#[test]
fn zst_auto_install_fails_on_invalid_zst() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img.zst");
    let target = dir.path().join("target.img");

    // Invalid zstd payload
    fs::write(&source, b"not-a-zst-file").unwrap();

    let err = install_image_maybe_compressed(&source, &target, true).unwrap_err();
    assert!(err.to_string().contains("zstd failed"));
}

#[test]
fn install_args_default_to_live_source() {
    let (source, target) = parse_install_args(Vec::<&str>::new());
    assert_eq!(source, default_live_source());
    assert_eq!(target, None);
}

#[test]
fn install_args_accept_source_and_target() {
    let (source, target) = parse_install_args(["source.img.zst", "/dev/vda"]);
    assert_eq!(source, PathBuf::from("source.img.zst"));
    assert_eq!(target, Some(PathBuf::from("/dev/vda")));
}

#[test]
fn installer_args_strip_tui_flag() {
    let (tui, source, target) = parse_installer_args([
        OsString::from("--tui"),
        OsString::from("a.img"),
        OsString::from("/dev/vdb"),
    ]);
    assert!(tui);
    assert_eq!(source, PathBuf::from("a.img"));
    assert_eq!(target, Some(PathBuf::from("/dev/vdb")));
}

use alpenglow_installer::{install_image, install_image_maybe_compressed, validate_target};
use std::fs;

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

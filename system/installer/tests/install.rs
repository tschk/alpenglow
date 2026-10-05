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
        0x28, 0xb5, 0x2f, 0xfd, 0x04, 0x58, 0xc9, 0x00, 0x00, 0x61, 0x6c, 0x70, 0x65, 0x6e, 0x67,
        0x6c, 0x6f, 0x77, 0x2d, 0x63, 0x6f, 0x6d, 0x70, 0x72, 0x65, 0x73, 0x73, 0x65, 0x64, 0x2d,
        0x74, 0x65, 0x73, 0x74, 0xc6, 0x62, 0xe6, 0x26,
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
    assert!(err.to_string().contains("Unknown frame descriptor"));
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

fn pattern(len: usize) -> Vec<u8> {
    (0..len).map(|i| (i % 251) as u8).collect()
}

#[test]
fn progress_reports_monotonic_bytes_and_finishes_at_the_total() {
    use alpenglow_installer::{install_image_with_progress, InstallProgress};
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    let target = dir.path().join("target.img");
    let data = pattern(9 * 1024 * 1024 + 123);
    fs::write(&source, &data).unwrap();

    let mut seen: Vec<InstallProgress> = Vec::new();
    let written =
        install_image_with_progress(&source, &target, true, |progress| seen.push(progress))
            .unwrap();

    assert_eq!(written, data.len() as u64);
    assert_eq!(fs::read(&target).unwrap(), data);
    assert!(
        seen.len() >= 3,
        "expected several updates, got {}",
        seen.len()
    );
    assert!(seen.iter().all(|p| p.total == Some(data.len() as u64)));
    assert!(seen
        .windows(2)
        .all(|pair| pair[0].written <= pair[1].written));
    assert_eq!(seen.first().unwrap().written, 0);
    let last = seen.last().unwrap();
    assert_eq!(last.written, data.len() as u64);
    assert_eq!(last.percent(), Some(100));
}

#[test]
fn progress_knows_the_decompressed_size_when_the_frame_records_it() {
    use alpenglow_installer::install_image_with_progress;
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img.zst");
    let target = dir.path().join("target.img");
    let data = pattern(5 * 1024 * 1024);
    // One-shot compression stores the content size in the frame header.
    fs::write(&source, zstd::bulk::compress(&data, 3).unwrap()).unwrap();

    let mut last = None;
    install_image_with_progress(&source, &target, true, |progress| last = Some(progress)).unwrap();

    assert_eq!(fs::read(&target).unwrap(), data);
    let last = last.unwrap();
    assert_eq!(last.total, Some(data.len() as u64));
    assert_eq!(last.percent(), Some(100));
}

#[test]
fn progress_total_is_unknown_for_streamed_zstd_but_the_data_is_intact() {
    use alpenglow_installer::install_image_with_progress;
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img.zst");
    let target = dir.path().join("target.img");
    let data = pattern(3 * 1024 * 1024);
    // Streaming compression cannot know the size up front.
    fs::write(&source, zstd::encode_all(&data[..], 3).unwrap()).unwrap();

    let mut last = None;
    install_image_with_progress(&source, &target, true, |progress| last = Some(progress)).unwrap();

    assert_eq!(fs::read(&target).unwrap(), data);
    let last = last.unwrap();
    assert_eq!(last.total, None);
    assert_eq!(last.percent(), None);
    assert_eq!(last.written, data.len() as u64);
}

#[test]
fn progress_install_still_refuses_non_block_targets_and_missing_sources() {
    use alpenglow_installer::install_image_with_progress;
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    let target = dir.path().join("target.img");
    fs::write(&source, b"alpenglow").unwrap();
    fs::write(&target, b"untouched").unwrap();
    let err = install_image_with_progress(&source, &target, false, |_| {}).unwrap_err();
    assert!(err.to_string().contains("refusing"));
    assert_eq!(fs::read(&target).unwrap(), b"untouched");

    let err = install_image_with_progress(&dir.path().join("nope.img"), &target, true, |_| {})
        .unwrap_err();
    assert!(err.to_string().contains("No such file"));
}

#[test]
fn plain_install_of_a_zst_named_file_stays_a_raw_copy() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("raw.img.zst");
    let target = dir.path().join("target.img");
    fs::write(&source, b"not actually compressed").unwrap();
    install_image(&source, &target, true).unwrap();
    assert_eq!(fs::read(&target).unwrap(), b"not actually compressed");
}

#[test]
fn percent_clamps_and_handles_zero_totals() {
    use alpenglow_installer::InstallProgress;
    let progress = |written, total| InstallProgress { written, total };
    assert_eq!(progress(0, Some(100)).percent(), Some(0));
    assert_eq!(progress(50, Some(100)).percent(), Some(50));
    assert_eq!(progress(500, Some(100)).percent(), Some(100));
    assert_eq!(progress(10, Some(0)).percent(), None);
    assert_eq!(progress(10, None).percent(), None);
}

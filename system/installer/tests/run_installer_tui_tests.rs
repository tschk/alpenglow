use alpenglow_installer::run_installer_with_draw;
use std::ffi::OsString;
use std::path::Path;

#[test]
fn test_tui_draw_fails() {
    let args: Vec<OsString> = vec![OsString::from("--tui")];
    let draw = |_: &Path, _: Option<&Path>| Err("UI error".to_string());
    assert_eq!(run_installer_with_draw(args, draw), 1);
}

#[test]
fn test_tui_draw_succeeds_install_fails() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    std::fs::write(&source, b"data").unwrap();

    let args: Vec<OsString> = vec![
        OsString::from("--tui"),
        OsString::from(source.to_str().unwrap()),
        OsString::from("/dev/invalid_target_xyz"),
    ];

    let mut draw_called = false;
    let draw = |s: &Path, t: Option<&Path>| {
        draw_called = true;
        assert_eq!(s, source.as_path());
        assert_eq!(t, Some(Path::new("/dev/invalid_target_xyz")));
        Ok(())
    };

    assert_eq!(run_installer_with_draw(args, draw), 1);
    assert!(draw_called);
}

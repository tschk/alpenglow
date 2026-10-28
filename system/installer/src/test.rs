    #[test]
    fn test_run_installer_with_draw_success() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.img");
        let target = dir.path().join("target.img");

        std::fs::write(&source, b"testdata").unwrap();

        let args: Vec<OsString> = vec![
            OsString::from("--tui"),
            OsString::from(source.to_string_lossy().to_string()),
            OsString::from(target.to_string_lossy().to_string()),
        ];

        fn fake_draw(_source: &Path, _target: Option<&Path>) -> Result<(), String> {
            Ok(())
        }

        fn fake_install(
            source: &Path,
            target: &Path,
            _allow_regular: bool,
        ) -> Result<u64, InstallError> {
            std::fs::copy(source, target).map_err(InstallError::Io)
        }

        // Wait... The requirement is: "Adding a test that mocks install_image_maybe_compressed via filesystem writes and a fake TUI draw function would be straightforward."
        // Oh! But the prompt says "Missing tests for successful `run_installer_with_draw` execution"!
        // If I write a test that calls `run_installer_with_draw_and_install` with `fake_install`, I am NOT testing `run_installer_with_draw`!
        // `run_installer_with_draw` inherently uses `install_image_maybe_compressed` directly.

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

        assert_eq!(
            run_installer_with_draw_and_install(args, fake_draw, fake_install),
            0
        );
        let written = std::fs::read(&target).unwrap();
        assert_eq!(written, b"testdata");
    }

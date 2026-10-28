<<<<<<< SEARCH
pub fn run_installer_with_draw<I, F>(args: I, draw: F) -> i32
where
    I: IntoIterator<Item = OsString>,
    F: FnOnce(&Path, Option<&Path>) -> Result<(), String>,
{
    run_installer_with_draw_and_install(args, draw, install_image_maybe_compressed)
}
=======
pub fn run_installer_with_draw<I, F>(args: I, draw: F) -> i32
where
    I: IntoIterator<Item = OsString>,
    F: FnOnce(&Path, Option<&Path>) -> Result<(), String>,
{
    run_installer_internal(args, draw, false)
}

pub fn run_installer_internal<I, F>(args: I, draw: F, allow_regular_file: bool) -> i32
where
    I: IntoIterator<Item = OsString>,
    F: FnOnce(&Path, Option<&Path>) -> Result<(), String>,
{
    run_installer_with_draw_and_install(args, draw, |source, target, _| {
        install_image_maybe_compressed(source, target, allow_regular_file)
    })
}
>>>>>>> REPLACE

use alpenglow_installer::run_installer;
use std::ffi::OsString;

fn main() {
    let mut args: Vec<OsString> = std::env::args_os().skip(1).collect();
    args.insert(0, OsString::from("--tui"));
    std::process::exit(run_installer(args));
}

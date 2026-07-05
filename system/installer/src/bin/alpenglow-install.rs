use alpenglow_installer::install_image;
use std::path::PathBuf;

fn main() {
    let mut args = std::env::args_os().skip(1);
    let source = args.next().map(PathBuf::from).unwrap_or_else(|| {
        eprintln!("usage: alpenglow-install <source.img> <target-disk>");
        std::process::exit(2);
    });
    let target = args.next().map(PathBuf::from).unwrap_or_else(|| {
        eprintln!("usage: alpenglow-install <source.img> <target-disk>");
        std::process::exit(2);
    });
    match install_image(&source, &target, false) {
        Ok(bytes) => println!("wrote {bytes} bytes to {}", target.display()),
        Err(err) => {
            eprintln!("install failed: {err}");
            std::process::exit(1);
        }
    }
}

use alpenglow_installer::install_image_maybe_compressed;
use std::path::PathBuf;

fn main() {
    let mut args = std::env::args_os().skip(1);
    let source = args.next().map(PathBuf::from).unwrap_or_else(|| {
        eprintln!("usage: alpenglow-install <source.img|source.img.zst> <target-disk>");
        std::process::exit(2);
    });
    let target = args.next().map(PathBuf::from).unwrap_or_else(|| {
        eprintln!("usage: alpenglow-install <source.img|source.img.zst> <target-disk>");
        std::process::exit(2);
    });
    match install_image_maybe_compressed(&source, &target, false) {
        Ok(bytes) => println!("wrote {bytes} bytes to {}", target.display()),
        Err(err) => {
            eprintln!("install failed: {err}");
            std::process::exit(1);
        }
    }
}

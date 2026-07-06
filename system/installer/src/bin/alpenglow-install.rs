use alpenglow_installer::{install_image_maybe_compressed, parse_install_args};

fn main() {
    let (source, target) = parse_install_args(std::env::args_os().skip(1));
    let Some(target) = target else {
        eprintln!("usage: alpenglow-install <source.img|source.img.zst> <target-disk>");
        std::process::exit(2);
    };
    match install_image_maybe_compressed(&source, &target, false) {
        Ok(bytes) => println!("wrote {bytes} bytes to {}", target.display()),
        Err(err) => {
            eprintln!("install failed: {err}");
            std::process::exit(1);
        }
    }
}

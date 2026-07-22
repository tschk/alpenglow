use alpenglow_installer::run_installer;

fn main() {
    std::process::exit(run_installer(std::env::args_os().skip(1)));
}

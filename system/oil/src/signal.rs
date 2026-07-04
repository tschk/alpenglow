use signal_hook::{consts::SIGINT, iterator::Signals};

pub fn install_handler() {
    let mut signals = Signals::new([SIGINT]).expect("Failed to register signal handler");
    std::thread::spawn(move || {
        if signals.forever().next().is_some() {
            eprintln!("\nInterrupted");
            std::process::exit(130);
        }
    });
}

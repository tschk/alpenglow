use std::sync::atomic::{AtomicBool, Ordering};

pub fn install_handler() {
    let running = std::sync::Arc::new(AtomicBool::new(true));
    let r = running.clone();
    let _ = ctrlc::set_handler(move || {
        if r.swap(false, Ordering::SeqCst) {
            eprintln!("\ninterrupted");
        } else {
            std::process::exit(130);
        }
    });
}

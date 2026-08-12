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

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;
    use std::env;

    #[test]
    fn test_signal_handler() {
        if env::var("TEST_SIGNAL_HANDLER_CHILD").is_ok() {
            install_handler();
            loop {
                std::thread::park();
            }
        }

        let exe = env::current_exe().unwrap();
        let mut child = Command::new(exe)
            .env("TEST_SIGNAL_HANDLER_CHILD", "1")
            .arg("signal::tests::test_signal_handler")
            .arg("--exact")
            .spawn()
            .expect("failed to spawn child");

        std::thread::sleep(std::time::Duration::from_millis(500));

        let pid = child.id();
        let status = Command::new("kill")
            .args(["-s", "INT", &pid.to_string()])
            .status()
            .expect("failed to run kill");
        assert!(status.success());

        let exit_status = child.wait().expect("failed to wait on child");
        assert_eq!(exit_status.code(), Some(130));
    }
}

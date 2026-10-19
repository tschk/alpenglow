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
    use std::env;
    use std::process::{Command, Stdio};

    #[test]
    fn test_signal_handler() {
        if env::var("TEST_SIGNAL_HANDLER_CHILD").is_ok() {
            install_handler();
            loop {
                std::thread::park();
            }
        }

        let exe = env::current_exe().unwrap();
        let child = Command::new(exe)
            .env("TEST_SIGNAL_HANDLER_CHILD", "1")
            .arg("signal::tests::test_signal_handler")
            .arg("--exact")
            .arg("--nocapture")
            .stderr(Stdio::piped())
            .spawn()
            .expect("failed to spawn child");

        std::thread::sleep(std::time::Duration::from_millis(500));

        let pid = child.id();
        let status = Command::new("kill")
            .args(["-s", "INT", &pid.to_string()])
            .status()
            .expect("failed to run kill");
        assert!(status.success());

        let output = child.wait_with_output().expect("failed to wait on child");
        assert_eq!(output.status.code(), Some(130));
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(stderr.contains("Interrupted"));
    }

    #[test]
    fn test_signal_handler_term() {
        if env::var("TEST_SIGNAL_HANDLER_CHILD_TERM").is_ok() {
            install_handler();
            loop {
                std::thread::park();
            }
        }

        let exe = env::current_exe().unwrap();
        let child = Command::new(exe)
            .env("TEST_SIGNAL_HANDLER_CHILD_TERM", "1")
            .arg("signal::tests::test_signal_handler_term")
            .arg("--exact")
            .arg("--nocapture")
            .stderr(Stdio::piped())
            .spawn()
            .expect("failed to spawn child");

        std::thread::sleep(std::time::Duration::from_millis(500));

        let pid = child.id();
        let status = Command::new("kill")
            .args(["-s", "TERM", &pid.to_string()])
            .status()
            .expect("failed to run kill");
        assert!(status.success());

        let output = child.wait_with_output().expect("failed to wait on child");
        use std::os::unix::process::ExitStatusExt;
        assert_eq!(output.status.signal(), Some(15));
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(!stderr.contains("Interrupted"));
    }
}

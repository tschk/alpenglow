#[cfg(feature = "gui")]
#[test]
fn test_alpenglow_install_gui_fallback() {
    use std::io::Read;
    use std::process::{Command, Stdio};
    use std::time::{Duration, Instant};

    let mut child = Command::new(env!("CARGO_BIN_EXE_alpenglow-install-gui"))
        .env_remove("WAYLAND_DISPLAY")
        .env_remove("DISPLAY")
        .stderr(Stdio::piped())
        .spawn()
        .expect("Failed to execute alpenglow-install-gui");

    let mut stderr_output = String::new();
    let mut stderr_pipe = child.stderr.take().unwrap();

    let start = Instant::now();
    let mut found_error = false;

    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = [0; 1024];
        while let Ok(n) = stderr_pipe.read(&mut buf) {
            if n == 0 { break; }
            tx.send(String::from_utf8_lossy(&buf[..n]).into_owned()).ok();
        }
    });

    while start.elapsed() < Duration::from_secs(5) {
        if let Ok(chunk) = rx.try_recv() {
            stderr_output.push_str(&chunk);
            if stderr_output.contains("Failed to open window") {
                found_error = true;
                break;
            }
        }
        std::thread::sleep(Duration::from_millis(50));
    }

    let _ = child.kill();
    let _ = child.wait();

    assert!(
        found_error,
        "The GUI fallback should print a 'Failed to open window' error within 5 seconds. Stderr was: {}", stderr_output
    );
}

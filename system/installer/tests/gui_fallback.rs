use std::process::Command;
use std::env;

#[test]
fn test_gui_fallback() {
    let mut bin_path = env::current_exe().unwrap();
    bin_path.pop(); // Pop off the executable name
    bin_path.pop(); // Pop off the deps directory
    bin_path.push("alpenglow-install-gui");

    let output = Command::new(&bin_path)
        .env("WAYLAND_DISPLAY", "")
        .env("DISPLAY", "")
        .output()
        .expect("Failed to execute alpenglow-install-gui");

    let stderr = String::from_utf8_lossy(&output.stderr);
    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("stderr: {}", stderr);
    println!("stdout: {}", stdout);

    assert!(stderr.contains("Failed to open window: neither DISPLAY nor WAYLAND_DISPLAY is set"));
    assert!(stderr.contains("Falling back to TUI..."));
    assert!(stderr.contains("usage: alpenglow-install"));
}

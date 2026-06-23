// Alpenglow Rust init — replaces the shell /init script
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::process::Command;
fn main() {
    run("mount", &["-t", "proc", "proc", "/proc"]);
    run("mount", &["-t", "sysfs", "sysfs", "/sys"]);
    run("mount", &["-t", "devtmpfs", "devtmpfs", "/dev"]);
    for d in &["/run", "/dev/shm", "/tmp", "/state", "/sysroot"] {
        let _ = std::fs::create_dir_all(d);
    }
    run("mount", &["-t", "tmpfs", "tmpfs", "/run"]);
    run("mount", &["-t", "tmpfs", "-o", "mode=1777,size=256m", "tmpfs", "/dev/shm"]);
    run("mount", &["-t", "tmpfs", "-o", "mode=1777", "tmpfs", "/tmp"]);
    let _ = std::fs::create_dir_all("/run/user/0");
    let _ = std::fs::set_permissions("/run/user/0", std::fs::Permissions::from_mode(0o700));
    for m in &["ext4", "virtio-blk", "virtio-net", "snd", "snd-hda-intel"] {
        match Command::new("modprobe").arg(m).status() {
            Ok(status) if !status.success() => {
                eprintln!("init: modprobe {} failed with status: {}", m, status);
            }
            Err(e) => {
                eprintln!("init: failed to execute modprobe {}: {}", m, e);
            }
            _ => {}
        }
    }
    println!(); println!("Alpenglow boot (rust-init)"); println!();
    let err = Command::new("/sbin/dinit")
        .args(["-d", "/etc/dinit.d", "-s", "-t", "shell-ttyS0"])
        .exec();
    eprintln!("init: dinit exec failed: {}", err);
    let _ = Command::new("/bin/sh").exec();
}
fn run(prog: &str, args: &[&str]) {
    if let Err(e) = Command::new(prog).args(args).status() {
        eprintln!("init: {} failed: {}", prog, e);
    }
}

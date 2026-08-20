// Alpenglow Rust init — replaces the shell /init script
use std::os::unix::fs::PermissionsExt;
use std::process::Command;
fn main() {
    run("mount", &["-t", "proc", "proc", "/proc"]);
    run("mount", &["-t", "sysfs", "sysfs", "/sys"]);
    run("mount", &["-t", "devtmpfs", "devtmpfs", "/dev"]);
    for d in &["/run", "/dev/shm", "/tmp", "/state", "/sysroot"] {
        if let Err(e) = std::fs::create_dir_all(d) {
            eprintln!("init: failed to create directory {}: {}", d, e);
        }
        let mode = if *d == "/dev/shm" || *d == "/tmp" {
            0o1777
        } else {
            0o755
        };
        if let Err(e) = std::fs::set_permissions(d, std::fs::Permissions::from_mode(mode)) {
            eprintln!("init: failed to set permissions for directory {}: {}", d, e);
        }
    }
    run("mount", &["-t", "tmpfs", "tmpfs", "/run"]);
    let mut shm_size = String::from("mode=1777,size=256m");
    if let Ok(meminfo) = std::fs::read_to_string("/proc/meminfo") {
        for line in meminfo.lines() {
            if line.starts_with("MemTotal:") {
                if let Some(kb_str) = line.split_whitespace().nth(1) {
                    if let Ok(kb) = kb_str.parse::<u64>() {
                        shm_size = format!("mode=1777,size={}k", kb / 2);
                    }
                }
                break;
            }
        }
    }
    run(
        "mount",
        &["-t", "tmpfs", "-o", &shm_size, "tmpfs", "/dev/shm"],
    );
    run(
        "mount",
        &["-t", "tmpfs", "-o", "mode=1777", "tmpfs", "/tmp"],
    );
    if let Err(e) = std::fs::create_dir_all("/run/user/0") {
        eprintln!("init: failed to create directory /run/user/0: {}", e);
    }
    if let Err(e) = std::os::unix::fs::chown("/run/user/0", Some(0), Some(0)) {
        eprintln!("init: failed to chown /run/user/0: {}", e);
    }
    if let Err(e) = std::fs::set_permissions("/run/user/0", std::fs::Permissions::from_mode(0o700))
    {
        eprintln!("init: failed to set permissions for /run/user/0: {}", e);
    }
    for m in &["ext4", "virtio-blk", "virtio-net", "snd", "snd-hda-intel"] {
        match Command::new("modprobe").arg(m).env_clear().status() {
            Ok(status) if !status.success() => {
                eprintln!("init: modprobe {} failed with status: {}", m, status);
            }
            Err(e) => {
                eprintln!("init: failed to execute modprobe {}: {}", m, e);
            }
            _ => {}
        }
    }
    println!();
    println!("Alpenglow boot (rust-init)");
    println!();
    let err = std::os::unix::process::CommandExt::exec(
        Command::new("/usr/sbin/dinit")
            .args(["-d", "/etc/dinit.d", "-s", "-t", "shell-ttyS0"])
            .env_clear(),
    );
    eprintln!("init: dinit exec failed: {}", err);
    std::process::exit(1);
}
fn run(prog: &str, args: &[&str]) {
    if let Err(e) = Command::new(prog).args(args).env_clear().status() {
        eprintln!("init: {} failed: {}", prog, e);
    }
}

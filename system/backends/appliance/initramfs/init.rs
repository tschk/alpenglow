// Alpenglow Rust init — replaces the shell /init script
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::process::Command;
fn sys_mount(source: &str, target: &str, fstype: &str, flags: std::ffi::c_ulong, data: &str) {
    extern "C" {
        fn mount(
            source: *const std::ffi::c_char,
            target: *const std::ffi::c_char,
            filesystemtype: *const std::ffi::c_char,
            mountflags: std::ffi::c_ulong,
            data: *const std::ffi::c_void,
        ) -> std::ffi::c_int;
    }

    let c_source = std::ffi::CString::new(source).unwrap();
    let c_target = std::ffi::CString::new(target).unwrap();
    let c_fstype = std::ffi::CString::new(fstype).unwrap();
    let c_data = if data.is_empty() {
        None
    } else {
        Some(std::ffi::CString::new(data).unwrap())
    };

    let data_ptr = match &c_data {
        Some(s) => s.as_ptr() as *const std::ffi::c_void,
        None => std::ptr::null(),
    };

    let res = unsafe {
        mount(
            c_source.as_ptr(),
            c_target.as_ptr(),
            c_fstype.as_ptr(),
            flags,
            data_ptr,
        )
    };

    if res != 0 {
        eprintln!(
            "init: failed to mount {} on {} ({}): {}",
            source,
            target,
            fstype,
            std::io::Error::last_os_error()
        );
    }
}

fn main() {
    sys_mount("proc", "/proc", "proc", 0, "");
    sys_mount("sysfs", "/sys", "sysfs", 0, "");
    sys_mount("devtmpfs", "/dev", "devtmpfs", 0, "");
    for d in &["/run", "/dev/shm", "/tmp", "/state", "/sysroot"] {
        if let Err(e) = std::fs::create_dir_all(d) {
            eprintln!("init: failed to create directory {}: {}", d, e);
        }
    }
    sys_mount("tmpfs", "/run", "tmpfs", 0, "");
    sys_mount("tmpfs", "/dev/shm", "tmpfs", 0, "mode=1777,size=256m");
    sys_mount("tmpfs", "/tmp", "tmpfs", 0, "mode=1777");
    if let Err(e) = std::fs::create_dir_all("/run/user/0") {
        eprintln!("init: failed to create directory /run/user/0: {}", e);
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
    let err = Command::new("/usr/sbin/dinit")
        .args(["-d", "/etc/dinit.d", "-s", "-t", "shell-ttyS0"])
        .env_clear()
        .exec();
    eprintln!("init: dinit exec failed: {}", err);
    let _ = Command::new("/usr/bin/sh").env_clear().exec();
}

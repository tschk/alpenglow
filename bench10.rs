use std::time::Instant;
use std::fs;
use std::path::PathBuf;

fn format_disk_size(sectors: u64) -> String {
    let bytes = sectors.saturating_mul(512);
    let gib = bytes as f64 / 1024.0 / 1024.0 / 1024.0;
    if gib >= 1.0 {
        format!("{gib:.1} GiB")
    } else {
        let mib = bytes as f64 / 1024.0 / 1024.0;
        format!("{mib:.0} MiB")
    }
}

fn is_install_disk_name(name: &str) -> bool {
    (name.starts_with("sd")
        || name.starts_with("vd")
        || name.starts_with("xvd")
        || name.starts_with("nvme")
        || name.starts_with("mmcblk"))
        && !name.contains("loop")
        && !name.contains("ram")
        && !name.contains("zram")
}

struct DiskChoice {
    path: PathBuf,
    name: String,
    detail: String,
}

fn discover_disks() -> Vec<DiskChoice> {
    let mut disks = fs::read_dir("/sys/block")
        .ok()
        .into_iter()
        .flat_map(|entries| entries.filter_map(Result::ok))
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            if !is_install_disk_name(&name) {
                return None;
            }
            let path = PathBuf::from("/dev").join(&name);
            if !path.exists() {
                return None;
            }
            let size = fs::read_to_string(entry.path().join("size")).ok();
            let model = fs::read_to_string(entry.path().join("device/model"))
                .ok()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty());
            let detail = match (
                model,
                size.and_then(|value| value.trim().parse::<u64>().ok()),
            ) {
                (Some(model), Some(sectors)) => {
                    format!("{model} - {}", format_disk_size(sectors))
                }
                (Some(model), None) => model,
                (None, Some(sectors)) => format_disk_size(sectors),
                (None, None) => "Block device".to_string(),
            };
            Some(DiskChoice {
                path,
                name: name.to_string(),
                detail,
            })
        })
        .collect::<Vec<_>>();
    disks.sort_by(|left, right| left.name.cmp(&right.name));
    disks
}

// In the current sandbox env, there are very few files in /sys/block that match the filter,
// so the overhead of reading is minimal (hence 50ms for 1000 iterations = 0.05ms per iteration).
// In a real system, discovering disks might take 1-10ms because there are multiple drives and sysfs accesses are slow.
// The best approach is wrapping the iteration in a single thread thread::scope or thread::spawn
// isn't viable because it needs to block to return Vec<DiskChoice>.
// Wait, `discover_disks` is called on app init AND refresh.
// Reusing a String buffer for file reading will reduce allocations.

// What if we use a thread pool or spawn threads just for reading the sizes/models?
fn discover_disks_parallel() -> Vec<DiskChoice> {
    let entries = match fs::read_dir("/sys/block") {
        Ok(iter) => iter.filter_map(Result::ok).collect::<Vec<_>>(),
        Err(_) => return vec![],
    };

    let mut disks: Vec<DiskChoice> = std::thread::scope(|s| {
        let mut handles = Vec::new();
        for entry in entries {
            handles.push(s.spawn(move || {
                let name = entry.file_name().to_string_lossy().to_string();
                if !is_install_disk_name(&name) {
                    return None;
                }
                let path = PathBuf::from("/dev").join(&name);
                if !path.exists() {
                    return None;
                }
                let size = fs::read_to_string(entry.path().join("size")).ok();
                let model = fs::read_to_string(entry.path().join("device/model"))
                    .ok()
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty());
                let detail = match (
                    model,
                    size.and_then(|value| value.trim().parse::<u64>().ok()),
                ) {
                    (Some(model), Some(sectors)) => {
                        format!("{model} - {}", format_disk_size(sectors))
                    }
                    (Some(model), None) => model,
                    (None, Some(sectors)) => format_disk_size(sectors),
                    (None, None) => "Block device".to_string(),
                };
                Some(DiskChoice {
                    path,
                    name: name.to_string(),
                    detail,
                })
            }));
        }

        handles.into_iter().filter_map(|h| h.join().unwrap()).collect()
    });

    disks.sort_by(|left, right| left.name.cmp(&right.name));
    disks
}

fn discover_disks_buffer_reuse() -> Vec<DiskChoice> {
    let mut buf = String::with_capacity(128);
    let mut disks = fs::read_dir("/sys/block")
        .ok()
        .into_iter()
        .flat_map(|entries| entries.filter_map(Result::ok))
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !is_install_disk_name(&name) {
                return None;
            }
            let path = PathBuf::from("/dev").join(&name);
            if !path.exists() {
                return None;
            }

            use std::io::Read;

            let size = {
                buf.clear();
                if let Ok(mut f) = fs::File::open(entry.path().join("size")) {
                    f.read_to_string(&mut buf).ok().and_then(|_| buf.trim().parse::<u64>().ok())
                } else {
                    None
                }
            };

            let model = {
                buf.clear();
                if let Ok(mut f) = fs::File::open(entry.path().join("device/model")) {
                    f.read_to_string(&mut buf).ok().map(|_| buf.trim().to_owned()).filter(|v| !v.is_empty())
                } else {
                    None
                }
            };

            let detail = match (model, size) {
                (Some(model), Some(sectors)) => {
                    format!("{model} - {}", format_disk_size(sectors))
                }
                (Some(model), None) => model,
                (None, Some(sectors)) => format_disk_size(sectors),
                (None, None) => "Block device".to_string(),
            };
            Some(DiskChoice {
                path,
                name,
                detail,
            })
        })
        .collect::<Vec<_>>();
    disks.sort_by(|left, right| left.name.cmp(&right.name));
    disks
}

fn main() {
    // Note: sandbox might only have loop devices, meaning is_install_disk_name fails immediately!
    // Let's print what is actually returned:
    println!("Found disks: {}", discover_disks().len());
}

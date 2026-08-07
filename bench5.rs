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

fn discover_disks_pre_filter() -> Vec<DiskChoice> {
    let entries = match fs::read_dir("/sys/block") {
        Ok(entries) => {
            let mut filtered = Vec::new();
            for entry in entries.filter_map(Result::ok) {
                let name = entry.file_name().to_string_lossy().to_string();
                if is_install_disk_name(&name) {
                    let path = PathBuf::from("/dev").join(&name);
                    if path.exists() {
                        filtered.push((entry, name, path));
                    }
                }
            }
            filtered
        }
        Err(_) => return Vec::new(),
    };

    let mut disks = Vec::with_capacity(entries.len());

    // We can use thread::scope for this to do parallel reads, which is much cheaper
    // than creating full threads per request.
    std::thread::scope(|s| {
        let mut handles = Vec::with_capacity(entries.len());
        for (entry, name, path) in entries {
            handles.push(s.spawn(move || {
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
                DiskChoice {
                    path,
                    name,
                    detail,
                }
            }));
        }

        for handle in handles {
            if let Ok(choice) = handle.join() {
                disks.push(choice);
            }
        }
    });

    disks.sort_by(|left, right| left.name.cmp(&right.name));
    disks
}

fn main() {
    let iters = 1000;

    let start = Instant::now();
    for _ in 0..iters {
        discover_disks();
    }
    println!("Baseline elapsed: {:?}", start.elapsed());

    let start = Instant::now();
    for _ in 0..iters {
        discover_disks_pre_filter();
    }
    println!("Scoped threads elapsed: {:?}", start.elapsed());
}

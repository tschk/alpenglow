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

fn discover_disks_buffer_optimized() -> Vec<DiskChoice> {
    let mut buf = String::with_capacity(128);
    let mut disks = Vec::new();

    if let Ok(entries) = fs::read_dir("/sys/block") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !is_install_disk_name(&name) {
                continue;
            }

            let path = PathBuf::from("/dev").join(&name);
            if !path.exists() {
                continue;
            }

            use std::io::Read;
            let mut f_size = None;
            let mut f_model = None;

            if let Ok(mut f) = fs::File::open(entry.path().join("size")) {
                buf.clear();
                if f.read_to_string(&mut buf).is_ok() {
                    f_size = buf.trim().parse::<u64>().ok();
                }
            }

            if let Ok(mut f) = fs::File::open(entry.path().join("device/model")) {
                buf.clear();
                if f.read_to_string(&mut buf).is_ok() {
                    let trimmed = buf.trim();
                    if !trimmed.is_empty() {
                        f_model = Some(trimmed.to_owned());
                    }
                }
            }

            let detail = match (f_model, f_size) {
                (Some(model), Some(sectors)) => {
                    format!("{model} - {}", format_disk_size(sectors))
                }
                (Some(model), None) => model,
                (None, Some(sectors)) => format_disk_size(sectors),
                (None, None) => "Block device".to_string(),
            };

            disks.push(DiskChoice {
                path,
                name,
                detail,
            });
        }
    }

    disks.sort_by(|left, right| left.name.cmp(&right.name));
    disks
}

fn main() {
    let iters = 1000;

    let start = Instant::now();
    for _ in 0..iters {
        discover_disks();
    }
    let baseline = start.elapsed();
    println!("Baseline elapsed: {:?}", baseline);

    let start = Instant::now();
    for _ in 0..iters {
        discover_disks_buffer_optimized();
    }
    let optimized = start.elapsed();
    println!("Optimized (buffer reuse, no flat_map overhead) elapsed: {:?}", optimized);
}

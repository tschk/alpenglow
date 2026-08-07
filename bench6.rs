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

// Optimization using single allocation for string reading
fn discover_disks_optimized() -> Vec<DiskChoice> {
    let mut buf = String::with_capacity(64);

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
                    f.read_to_string(&mut buf).ok().map(|_| buf.trim().to_string()).filter(|v| !v.is_empty())
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
                name: name.to_string(),
                detail,
            })
        })
        .collect::<Vec<_>>();
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
        discover_disks_optimized();
    }
    let optimized = start.elapsed();
    println!("Optimized (buffer reuse) elapsed: {:?}", optimized);

    if optimized < baseline {
        let improvement = (1.0 - (optimized.as_secs_f64() / baseline.as_secs_f64())) * 100.0;
        println!("Improvement: {:.2}%", improvement);
    }
}

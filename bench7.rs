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

// Full background thread with gpui sync
// Wait, we can't test gpui here easily, but we can measure thread spawning overhead vs sequential execution
// But we saw scoped threads were 4x slower. Wait, scoped threads for *each file read* is slower because there's only 2 files to read!
// The optimal way to run this without blocking the UI thread is to wrap the *entire* `discover_disks` in `cx.background_executor().spawn()`.
// This moves the I/O off the main thread completely. Let's see how `discover_disks` is used in the app.

fn main() {
}

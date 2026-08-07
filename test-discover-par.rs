use std::fs;
use std::path::PathBuf;
use std::time::Instant;
use std::thread;

fn is_install_disk_name(name: &str) -> bool {
    // Dummy implementation for benchmarking
    name.starts_with("loop") || name.starts_with("sd") || name.starts_with("nvme")
}

fn format_disk_size(sectors: u64) -> String {
    format!("{} MB", sectors / 2048)
}

struct DiskChoice {
    path: PathBuf,
    name: String,
    detail: String,
}

fn discover_disks() -> Vec<DiskChoice> {
    let mut disks: Vec<DiskChoice> = thread::scope(|s| {
        let entries = fs::read_dir("/sys/block")
            .ok()
            .into_iter()
            .flat_map(|entries| entries.filter_map(Result::ok))
            .filter_map(|entry| {
                let name = entry.file_name().to_string_lossy().to_string();
                if !is_install_disk_name(&name) {
                    return None;
                }
                let path = PathBuf::from("/dev").join(&name);
                Some((name, path, entry.path()))
            })
            .collect::<Vec<_>>();

        let mut handles = vec![];
        for (name, path, entry_path) in entries {
            let handle = s.spawn(move || {
                let size = fs::read_to_string(entry_path.join("size")).ok();
                let model = fs::read_to_string(entry_path.join("device/model"))
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
            });
            handles.push(handle);
        }

        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });

    disks.sort_by(|left, right| left.name.cmp(&right.name));
    disks
}

fn main() {
    let start = Instant::now();
    for _ in 0..100 {
        discover_disks();
    }
    let duration = start.elapsed();
    println!("Parallel (100 iterations): {:?}", duration);
}

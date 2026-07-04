use std::env;
use std::path::PathBuf;
use std::time::Duration;

use alpenglow_netd::{read_snapshot, write_snapshot};
use notify::recommended_watcher;
use notify::{EventKind, RecursiveMode, Watcher};

const DEFAULT_SYS_CLASS_NET: &str = "/sys/class/net";
const DEFAULT_STATE_JSON: &str = "/run/alpenglow/netd/interfaces.json";
const DEFAULT_RUNTIME_ENV: &str = "/run/alpenglow/netd/runtime-state.env";

fn main() {
    if let Err(error) = run() {
        eprintln!("alpenglow-netd: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let sys_class_net = env::var_os("ALPENGLOW_NETD_SYS_CLASS_NET")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_SYS_CLASS_NET));

    let state_json = env::var_os("ALPENGLOW_NETD_STATE_JSON")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_STATE_JSON));

    let runtime_env = env::var_os("ALPENGLOW_NETD_RUNTIME_ENV")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_RUNTIME_ENV));

    let sys_class_net_clone = sys_class_net.clone();
    let state_json_clone = state_json.clone();
    let runtime_env_clone = runtime_env.clone();

    let mut watcher = recommended_watcher(move |res: Result<notify::Event, notify::Error>| {
        if let Ok(event) = res {
            if matches!(
                event.kind,
                EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
            ) {
                if let Err(error) =
                    update_snapshot(&sys_class_net_clone, &state_json_clone, &runtime_env_clone)
                {
                    eprintln!("alpenglow-netd: {error}");
                }
            }
        }
    })
    .map_err(|e| format!("Failed to create watcher: {e}"))?;

    watcher
        .watch(&sys_class_net, RecursiveMode::NonRecursive)
        .map_err(|e| format!("Failed to watch {sys_class_net:?}: {e}"))?;

    update_snapshot(&sys_class_net, &state_json, &runtime_env)?;

    loop {
        std::thread::sleep(Duration::from_secs(3600));
    }
}

fn update_snapshot(
    sys_class_net: &PathBuf,
    state_json: &PathBuf,
    runtime_env: &PathBuf,
) -> Result<(), String> {
    let snapshot = read_snapshot(sys_class_net)
        .map_err(|error| format!("read {}: {error}", sys_class_net.display()))?;
    write_snapshot(&snapshot, state_json, runtime_env).map_err(|error| {
        format!(
            "write {} and {}: {error}",
            state_json.display(),
            runtime_env.display()
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn create_temp_dir(name: &str) -> PathBuf {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("Time went backwards")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("alpenglow-netd-test-{}-{}", name, ts));
        fs::create_dir_all(&path).expect("failed to create temp dir");
        path
    }

    #[test]
    fn test_update_snapshot_success() {
        let temp_dir = create_temp_dir("success");

        let sys_class_net = temp_dir.join("sys_class_net");
        fs::create_dir_all(&sys_class_net).expect("failed to create sys_class_net");

        let state_json = temp_dir.join("state.json");
        let runtime_env = temp_dir.join("runtime.env");

        let result = update_snapshot(&sys_class_net, &state_json, &runtime_env);

        assert!(result.is_ok(), "update_snapshot failed: {:?}", result.err());
        assert!(state_json.exists(), "state_json should exist");
        assert!(runtime_env.exists(), "runtime_env should exist");

        fs::remove_dir_all(&temp_dir).expect("failed to clean up");
    }

    #[test]
    fn test_update_snapshot_read_error() {
        let temp_dir = create_temp_dir("read-err");

        let sys_class_net = temp_dir.join("sys_class_net_file");
        fs::write(&sys_class_net, "not a dir").expect("failed to write file");

        let state_json = temp_dir.join("state.json");
        let runtime_env = temp_dir.join("runtime.env");

        let result = update_snapshot(&sys_class_net, &state_json, &runtime_env);

        let err_msg = result.expect_err("expected update_snapshot to fail");
        assert!(
            err_msg.starts_with(&format!("read {}", sys_class_net.display())),
            "unexpected error message: {}",
            err_msg
        );

        fs::remove_dir_all(&temp_dir).expect("failed to clean up");
    }

    #[test]
    fn test_update_snapshot_write_error() {
        let temp_dir = create_temp_dir("write-err");

        let sys_class_net = temp_dir.join("sys_class_net");
        fs::create_dir_all(&sys_class_net).expect("failed to create sys_class_net");

        let state_json = temp_dir.join("state.json");
        fs::create_dir_all(&state_json).expect("failed to create dir for state_json");

        let runtime_env = temp_dir.join("runtime.env");

        let result = update_snapshot(&sys_class_net, &state_json, &runtime_env);

        let err_msg = result.expect_err("expected update_snapshot to fail");
        assert!(
            err_msg.starts_with(&format!(
                "write {} and {}:",
                state_json.display(),
                runtime_env.display()
            )),
            "unexpected error message: {}",
            err_msg
        );

        fs::remove_dir_all(&temp_dir).expect("failed to clean up");
    }
}

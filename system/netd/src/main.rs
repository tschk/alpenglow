use std::env;
use std::path::PathBuf;
use std::time::Duration;

use alpenglow_netd::{read_snapshot, write_snapshot};
use notify::{EventKind, RecursiveMode, Watcher};
use notify::recommended_watcher;

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
            if matches!(event.kind, EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)) {
                if let Err(error) = update_snapshot(&sys_class_net_clone, &state_json_clone, &runtime_env_clone) {
                    eprintln!("alpenglow-netd: {error}");
                }
            }
        }
    }).map_err(|e| format!("Failed to create watcher: {e}"))?;
    
    watcher.watch(&sys_class_net, RecursiveMode::NonRecursive)
        .map_err(|e| format!("Failed to watch {sys_class_net:?}: {e}"))?;
    
    update_snapshot(&sys_class_net, &state_json, &runtime_env)?;
    
    loop {
        std::thread::sleep(Duration::from_secs(3600));
    }
}

fn update_snapshot(sys_class_net: &PathBuf, state_json: &PathBuf, runtime_env: &PathBuf) -> Result<(), String> {
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

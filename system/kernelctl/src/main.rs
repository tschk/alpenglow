use std::collections::BTreeMap;
use std::env;
use std::io;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use tokio::fs;
use tokio::process::Command;
use tokio::task::JoinSet;

const DEFAULT_POLICY: &str = "/etc/alpenglow/kernel-policy.json";
const DEFAULT_RUNTIME_STATE: &str = "/run/alpenglow/runtime-state.env";
const DEFAULT_CGROUP_FS: &str = "/sys/fs/cgroup";
const POLICY_TASK_LIMIT: usize = 8;

#[derive(Debug, Deserialize)]
struct KernelPolicy {
    profile: String,
    groups: Vec<CgroupPolicy>,
    sysctl: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Deserialize)]
struct CgroupPolicy {
    id: String,
    path: String,
    cpu_weight: Option<u64>,
    io_weight: Option<u64>,
    memory_high: Option<String>,
    memory_max: Option<String>,
    pids_max: Option<u64>,
}

#[derive(Debug)]
struct Args {
    command: CommandMode,
    policy: PathBuf,
    runtime_state: PathBuf,
    cgroup_fs: PathBuf,
    dry_run: bool,
}

#[derive(Debug)]
enum CommandMode {
    Apply,
    Attach { group: String, pid: u32 },
}

#[tokio::main]
async fn main() {
    if let Err(error) = run(parse_args(env::args().skip(1))).await {
        eprintln!("alpenglow-kernelctl: {error}");
        std::process::exit(1);
    }
}

fn parse_args<I>(args: I) -> Args
where
    I: IntoIterator<Item = String>,
{
    let mut policy = env::var_os("ALPENGLOW_KERNEL_POLICY_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_POLICY));
    let mut runtime_state = env::var_os("ALPENGLOW_RUNTIME_STATE_ENV")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_RUNTIME_STATE));
    let mut cgroup_fs = env::var_os("ALPENGLOW_CGROUP_FS")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_CGROUP_FS));
    let mut command = CommandMode::Apply;
    let mut dry_run = false;
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "apply" => command = CommandMode::Apply,
            "attach" => {
                let mut group = None;
                let mut pid = None;
                while let Some(value) = iter.next() {
                    match value.as_str() {
                        "--group" => group = iter.next(),
                        "--pid" => {
                            pid = iter.next().and_then(|pid| pid.parse::<u32>().ok());
                        }
                        "--cgroup-fs" => {
                            if let Some(value) = iter.next() {
                                cgroup_fs = PathBuf::from(value);
                            }
                        }
                        "--dry-run" => dry_run = true,
                        _ => {}
                    }
                }
                command = CommandMode::Attach {
                    group: group.unwrap_or_default(),
                    pid: pid.unwrap_or_default(),
                };
                break;
            }
            "--policy" => {
                if let Some(value) = iter.next() {
                    policy = PathBuf::from(value);
                }
            }
            "--runtime-state" => {
                if let Some(value) = iter.next() {
                    runtime_state = PathBuf::from(value);
                }
            }
            "--cgroup-fs" => {
                if let Some(value) = iter.next() {
                    cgroup_fs = PathBuf::from(value);
                }
            }
            "--dry-run" => dry_run = true,
            _ => {}
        }
    }
    Args {
        command,
        policy,
        runtime_state,
        cgroup_fs,
        dry_run,
    }
}

async fn run(args: Args) -> Result<(), String> {
    if let CommandMode::Attach { group, pid } = &args.command {
        return attach_to_cgroup(&args.cgroup_fs, group, *pid, args.dry_run)
            .await
            .map_err(|error| format!("attach {group}/{pid}: {error}"));
    }
    let policy = read_policy(&args.policy).await?;
    let (_, _, cgroups_state) = tokio::try_join!(
        load_kernel_modules(args.dry_run),
        apply_sysctls(&policy.sysctl, args.dry_run),
        apply_cgroups(&policy.groups, &args.cgroup_fs, args.dry_run),
    )?;
    record_runtime_state(
        &args.runtime_state,
        "ALPENGLOW_KERNEL_POLICY_FILE",
        args.policy.display(),
    )
    .await
    .map_err(|error| format!("runtime state: {error}"))?;
    record_runtime_state(
        &args.runtime_state,
        "ALPENGLOW_KERNEL_POLICY_CGROUPS",
        cgroups_state,
    )
    .await
    .map_err(|error| format!("runtime state: {error}"))?;
    record_runtime_state(
        &args.runtime_state,
        "ALPENGLOW_KERNEL_POLICY_PROFILE",
        &policy.profile,
    )
    .await
    .map_err(|error| format!("runtime state: {error}"))?;
    Ok(())
}

async fn read_policy(path: &Path) -> Result<KernelPolicy, String> {
    let raw = fs::read_to_string(path)
        .await
        .map_err(|error| format!("read {}: {error}", path.display()))?;
    serde_json::from_str(&raw).map_err(|error| format!("parse {}: {error}", path.display()))
}

async fn load_kernel_modules(dry_run: bool) -> Result<(), String> {
    let mut tasks = JoinSet::new();
    for module in ["virtio_pci", "virtio_net", "virtio_rng", "virtio_gpu"] {
        tasks.spawn(load_kernel_module(module, dry_run));
    }
    while let Some(result) = tasks.join_next().await {
        result.map_err(|error| format!("module task: {error}"))?;
    }
    Ok(())
}

async fn load_kernel_module(module: &'static str, dry_run: bool) {
    if dry_run {
        return;
    }
    let _ = Command::new("modprobe").arg(module).status().await;
}

async fn apply_sysctls(sysctl: &BTreeMap<String, String>, dry_run: bool) -> Result<(), String> {
    let mut tasks = JoinSet::new();
    for (key, value) in sysctl {
        while tasks.len() >= POLICY_TASK_LIMIT {
            join_policy_task(&mut tasks, "sysctl").await?;
        }
        let key = key.clone();
        let value = value.clone();
        tasks.spawn(async move {
            apply_sysctl(&key, &value, dry_run)
                .await
                .map_err(|error| format!("{key}: {error}"))
        });
    }
    while let Some(result) = tasks.join_next().await {
        result.map_err(|error| format!("sysctl task: {error}"))??;
    }
    Ok(())
}

async fn apply_sysctl(key: &str, value: &str, dry_run: bool) -> io::Result<()> {
    if dry_run {
        return Ok(());
    }
    let path = Path::new("/proc/sys").join(key.replace('.', "/"));
    if fs::try_exists(&path).await? {
        fs::write(path, format!("{value}\n")).await?;
    }
    Ok(())
}

async fn apply_cgroups(
    groups: &[CgroupPolicy],
    cgroup_fs: &Path,
    dry_run: bool,
) -> Result<&'static str, String> {
    if !fs::try_exists(cgroup_fs.join("cgroup.controllers"))
        .await
        .map_err(|error| format!("cgroup policy: {error}"))?
    {
        return Ok("unavailable");
    }
    if dry_run {
        return Ok("active");
    }
    fs::create_dir_all(cgroup_fs.join("alpenglow"))
        .await
        .map_err(|error| format!("cgroup policy: {error}"))?;
    enable_controllers(cgroup_fs).await;
    let mut tasks = JoinSet::new();
    for group in groups {
        while tasks.len() >= POLICY_TASK_LIMIT {
            join_policy_task(&mut tasks, "cgroup").await?;
        }
        let cgroup_fs = cgroup_fs.to_path_buf();
        let group = group.clone();
        tasks.spawn(async move {
            apply_group(&cgroup_fs, &group)
                .await
                .map_err(|error| format!("{}: {error}", group.id))
        });
    }
    while let Some(result) = tasks.join_next().await {
        result.map_err(|error| format!("cgroup task: {error}"))??;
    }
    Ok("active")
}

async fn join_policy_task(
    tasks: &mut JoinSet<Result<(), String>>,
    label: &str,
) -> Result<(), String> {
    if let Some(result) = tasks.join_next().await {
        result.map_err(|error| format!("{label} task: {error}"))??;
    }
    Ok(())
}

async fn enable_controllers(cgroup_fs: &Path) {
    let subtree_control = cgroup_fs.join("cgroup.subtree_control");
    for controller in ["cpu", "io", "memory", "pids"] {
        let _ = fs::write(&subtree_control, format!("+{controller}\n")).await;
    }
}

async fn apply_group(cgroup_fs: &Path, group: &CgroupPolicy) -> io::Result<()> {
    let path = cgroup_fs.join(&group.path);
    fs::create_dir_all(&path).await?;
    write_optional(&path, "cpu.weight", group.cpu_weight).await?;
    write_optional(&path, "io.weight", group.io_weight).await?;
    write_optional_string(&path, "memory.high", group.memory_high.as_deref()).await?;
    write_optional_string(&path, "memory.max", group.memory_max.as_deref()).await?;
    write_optional(&path, "pids.max", group.pids_max).await?;
    Ok(())
}

async fn write_optional(path: &Path, file: &str, value: Option<u64>) -> io::Result<()> {
    if let Some(value) = value {
        write_optional_string(path, file, Some(&value.to_string())).await?;
    }
    Ok(())
}

async fn write_optional_string(path: &Path, file: &str, value: Option<&str>) -> io::Result<()> {
    let target = path.join(file);
    if let Some(value) = value {
        if fs::try_exists(&target).await? {
            write_kernel_file(&target, value).await?;
        }
    }
    Ok(())
}

async fn write_kernel_file(path: &Path, value: &str) -> io::Result<()> {
    match fs::write(path, format!("{value}\n")).await {
        Ok(()) => Ok(()),
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::PermissionDenied
                    | io::ErrorKind::NotFound
                    | io::ErrorKind::Unsupported
            ) =>
        {
            Ok(())
        }
        Err(error) => Err(error),
    }
}

async fn record_runtime_state(
    path: &Path,
    key: &str,
    value: impl std::fmt::Display,
) -> io::Result<()> {
    let mut values = BTreeMap::new();
    if let Ok(raw) = fs::read_to_string(path).await {
        for line in raw.lines() {
            if let Some((existing_key, existing_value)) = line.split_once('=') {
                values.insert(existing_key.to_string(), existing_value.to_string());
            }
        }
    }
    values.insert(key.to_string(), value.to_string());
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).await?;
    }
    let mut rendered = String::new();
    for (key, value) in values {
        rendered.push_str(&key);
        rendered.push('=');
        rendered.push_str(&value);
        rendered.push('\n');
    }
    fs::write(path, rendered).await
}

async fn attach_to_cgroup(
    cgroup_fs: &Path,
    group: &str,
    pid: u32,
    dry_run: bool,
) -> io::Result<()> {
    if group.is_empty() || pid == 0 || dry_run {
        return Ok(());
    }
    let path = cgroup_fs.join("alpenglow").join(group);
    if fs::try_exists(cgroup_fs.join("cgroup.controllers")).await? {
        fs::create_dir_all(&path).await?;
        write_kernel_file(&path.join("cgroup.procs"), &pid.to_string()).await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs as std_fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn parses_cli_overrides() {
        let args = parse_args([
            "--policy".to_string(),
            "/tmp/policy.json".to_string(),
            "--runtime-state".to_string(),
            "/tmp/state.env".to_string(),
            "--cgroup-fs".to_string(),
            "/tmp/cgroup".to_string(),
            "--dry-run".to_string(),
        ]);
        assert!(matches!(args.command, CommandMode::Apply));
        assert_eq!(args.policy, PathBuf::from("/tmp/policy.json"));
        assert_eq!(args.runtime_state, PathBuf::from("/tmp/state.env"));
        assert_eq!(args.cgroup_fs, PathBuf::from("/tmp/cgroup"));
        assert!(args.dry_run);
    }

    #[tokio::test]
    async fn parses_attach_command() {
        let args = parse_args([
            "attach".to_string(),
            "--group".to_string(),
            "renderer".to_string(),
            "--pid".to_string(),
            "42".to_string(),
            "--cgroup-fs".to_string(),
            "/tmp/cgroup".to_string(),
        ]);
        assert_eq!(args.cgroup_fs, PathBuf::from("/tmp/cgroup"));
        match args.command {
            CommandMode::Attach { group, pid } => {
                assert_eq!(group, "renderer");
                assert_eq!(pid, 42);
            }
            CommandMode::Apply => panic!("expected attach command"),
        }
    }

    #[tokio::test]
    async fn dry_run_records_policy_state() {
        let root = temp_root("alpenglow-kernelctl-dry-run");
        std_fs::create_dir_all(root.join("cgroup")).unwrap();
        std_fs::write(
            root.join("cgroup/cgroup.controllers"),
            "cpu io memory pids\n",
        )
        .unwrap();
        let policy = root.join("policy.json");
        std_fs::write(
            &policy,
            r#"{
              "profile": "internet-appliance",
              "groups": [{"id":"renderer","path":"alpenglow/renderer","cpu_weight":800}],
              "sysctl": {"net.core.somaxconn": "4096"}
            }"#,
        )
        .unwrap();
        let runtime_state = root.join("state.env");
        run(Args {
            command: CommandMode::Apply,
            policy,
            runtime_state: runtime_state.clone(),
            cgroup_fs: root.join("cgroup"),
            dry_run: true,
        })
        .await
        .unwrap();
        let state = std_fs::read_to_string(runtime_state).unwrap();
        assert!(state.contains("ALPENGLOW_KERNEL_POLICY_PROFILE=internet-appliance"));
        assert!(state.contains("ALPENGLOW_KERNEL_POLICY_CGROUPS=active"));
    }

    #[tokio::test]
    async fn attach_command_writes_pid_to_group() {
        let root = temp_root("alpenglow-kernelctl-attach");
        let cgroup = root.join("cgroup");
        std_fs::create_dir_all(cgroup.join("alpenglow/renderer")).unwrap();
        std_fs::write(cgroup.join("cgroup.controllers"), "cpu io memory pids\n").unwrap();
        std_fs::write(cgroup.join("alpenglow/renderer/cgroup.procs"), "").unwrap();
        run(Args {
            command: CommandMode::Attach {
                group: "renderer".to_string(),
                pid: 42,
            },
            policy: root.join("policy.json"),
            runtime_state: root.join("state.env"),
            cgroup_fs: cgroup.clone(),
            dry_run: false,
        })
        .await
        .unwrap();
        assert_eq!(
            std_fs::read_to_string(cgroup.join("alpenglow/renderer/cgroup.procs")).unwrap(),
            "42\n"
        );
    }

    #[tokio::test]
    async fn cgroup_policy_applies_independent_groups() {
        let root = temp_root("alpenglow-kernelctl-cgroups");
        let cgroup = root.join("cgroup");
        std_fs::create_dir_all(cgroup.join("alpenglow/system")).unwrap();
        std_fs::create_dir_all(cgroup.join("alpenglow/renderer")).unwrap();
        std_fs::write(cgroup.join("cgroup.controllers"), "cpu io memory pids\n").unwrap();
        std_fs::write(cgroup.join("cgroup.subtree_control"), "").unwrap();
        std_fs::write(cgroup.join("alpenglow/system/cpu.weight"), "").unwrap();
        std_fs::write(cgroup.join("alpenglow/system/pids.max"), "").unwrap();
        std_fs::write(cgroup.join("alpenglow/renderer/memory.high"), "").unwrap();
        let groups = vec![
            CgroupPolicy {
                id: "system".to_string(),
                path: "alpenglow/system".to_string(),
                cpu_weight: Some(100),
                io_weight: None,
                memory_high: None,
                memory_max: None,
                pids_max: Some(128),
            },
            CgroupPolicy {
                id: "renderer".to_string(),
                path: "alpenglow/renderer".to_string(),
                cpu_weight: None,
                io_weight: None,
                memory_high: Some("1536M".to_string()),
                memory_max: None,
                pids_max: None,
            },
        ];
        let state = apply_cgroups(&groups, &cgroup, false).await.unwrap();
        assert_eq!(state, "active");
        assert_eq!(
            std_fs::read_to_string(cgroup.join("alpenglow/system/cpu.weight")).unwrap(),
            "100\n"
        );
        assert_eq!(
            std_fs::read_to_string(cgroup.join("alpenglow/system/pids.max")).unwrap(),
            "128\n"
        );
        assert_eq!(
            std_fs::read_to_string(cgroup.join("alpenglow/renderer/memory.high")).unwrap(),
            "1536M\n"
        );
    }

    #[tokio::test]
    async fn cgroup_policy_reports_unavailable_without_cgroup_v2() {
        let root = temp_root("alpenglow-kernelctl-cgroups-unavailable");
        let cgroup = root.join("cgroup");
        std_fs::create_dir_all(&cgroup).unwrap();
        let state = apply_cgroups(&[], &cgroup, false).await.unwrap();
        assert_eq!(state, "unavailable");
    }

    fn temp_root(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = env::temp_dir().join(format!("{name}-{nanos}"));
        std_fs::create_dir_all(&path).unwrap();
        path
    }
}

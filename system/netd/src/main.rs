use std::env;
use std::path::PathBuf;
use std::thread;
use std::time::Duration;

use sol_netd::{read_snapshot, write_snapshot};

const DEFAULT_SYS_CLASS_NET: &str = "/sys/class/net";
const DEFAULT_STATE_JSON: &str = "/run/soliloquy/netd/interfaces.json";
const DEFAULT_RUNTIME_ENV: &str = "/run/soliloquy/netd/runtime-state.env";

#[derive(Debug)]
struct Args {
    sys_class_net: PathBuf,
    state_json: PathBuf,
    runtime_env: PathBuf,
    interval: Duration,
    samples: Option<u64>,
}

fn main() {
    if let Err(error) = run(parse_args(env::args().skip(1))) {
        eprintln!("sol-netd: {error}");
        std::process::exit(1);
    }
}

fn parse_args<I>(args: I) -> Args
where
    I: IntoIterator<Item = String>,
{
    let mut parsed = Args {
        sys_class_net: env::var_os("SOLILOQUY_NETD_SYS_CLASS_NET")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_SYS_CLASS_NET)),
        state_json: env::var_os("SOLILOQUY_NETD_STATE_JSON")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_STATE_JSON)),
        runtime_env: env::var_os("SOLILOQUY_NETD_RUNTIME_ENV")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_RUNTIME_ENV)),
        interval: Duration::from_secs(
            env::var("SOLILOQUY_NETD_INTERVAL_SECS")
                .ok()
                .and_then(|value| value.parse().ok())
                .unwrap_or(5),
        ),
        samples: None,
    };
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--sys-class-net" => {
                if let Some(value) = iter.next() {
                    parsed.sys_class_net = PathBuf::from(value);
                }
            }
            "--state-json" => {
                if let Some(value) = iter.next() {
                    parsed.state_json = PathBuf::from(value);
                }
            }
            "--runtime-env" => {
                if let Some(value) = iter.next() {
                    parsed.runtime_env = PathBuf::from(value);
                }
            }
            "--interval-secs" => {
                if let Some(value) = iter.next().and_then(|value| value.parse().ok()) {
                    parsed.interval = Duration::from_secs(value);
                }
            }
            "--samples" => {
                parsed.samples = iter.next().and_then(|value| value.parse().ok());
            }
            "--once" => parsed.samples = Some(1),
            _ => {}
        }
    }
    parsed
}

fn run(args: Args) -> Result<(), String> {
    let mut remaining = args.samples;
    loop {
        let snapshot = read_snapshot(&args.sys_class_net)
            .map_err(|error| format!("read {}: {error}", args.sys_class_net.display()))?;
        write_snapshot(&snapshot, &args.state_json, &args.runtime_env).map_err(|error| {
            format!(
                "write {} and {}: {error}",
                args.state_json.display(),
                args.runtime_env.display()
            )
        })?;
        if let Some(samples) = remaining.as_mut() {
            *samples = samples.saturating_sub(1);
            if *samples == 0 {
                return Ok(());
            }
        }
        thread::sleep(args.interval);
    }
}

use serde::Serialize;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct NetworkSnapshot {
    pub generated_unix_ms: u64,
    pub interfaces: Vec<NetworkInterface>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct NetworkInterface {
    pub name: String,
    pub index: Option<u32>,
    #[serde(rename = "kind")]
    pub kind: InterfaceKind,
    #[serde(rename = "mac-address")]
    pub mac_address: Option<String>,
    pub operstate: OperState,
    pub mtu: Option<u32>,
    pub carrier: Option<bool>,
    #[serde(rename = "speed-mbps")]
    pub speed_mbps: Option<u32>,
    #[serde(rename = "rx-bytes")]
    pub rx_bytes: Option<u64>,
    #[serde(rename = "tx-bytes")]
    pub tx_bytes: Option<u64>,
    #[serde(rename = "flags-hex")]
    pub flags_hex: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum InterfaceKind {
    Loopback,
    Ethernet,
    Wireless,
    Other(i32),
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum OperState {
    Up,
    Down,
    Dormant,
    #[serde(rename = "lower-layer-down")]
    LowerLayerDown,
    #[serde(rename = "not-present")]
    NotPresent,
    Testing,
    Unknown,
}

pub fn read_snapshot(sys_class_net: impl AsRef<Path>) -> io::Result<NetworkSnapshot> {
    let mut interfaces = Vec::new();
    let root = sys_class_net.as_ref();
    if !root.exists() {
        return Ok(NetworkSnapshot {
            generated_unix_ms: now_unix_ms(),
            interfaces,
        });
    }
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        interfaces.push(read_interface(&name, &path)?);
    }
    interfaces.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(NetworkSnapshot {
        generated_unix_ms: now_unix_ms(),
        interfaces,
    })
}

pub fn render_json(snapshot: &NetworkSnapshot) -> String {
    serde_json::to_string_pretty(snapshot).unwrap_or_default()
}

pub fn render_runtime_env(snapshot: &NetworkSnapshot) -> String {
    let default = snapshot
        .interfaces
        .iter()
        .find(|interface| interface.name != "lo" && interface.operstate == OperState::Up)
        .or_else(|| {
            snapshot
                .interfaces
                .iter()
                .find(|interface| interface.operstate == OperState::Up)
        })
        .map(|interface| interface.name.as_str())
        .unwrap_or("");
    let up_count = snapshot
        .interfaces
        .iter()
        .filter(|interface| interface.operstate == OperState::Up)
        .count();
    format!(
        "ALPENGLOW_NETD_INTERFACES={}\nALPENGLOW_NETD_UP_INTERFACES={}\nALPENGLOW_NETD_DEFAULT_INTERFACE={}\nALPENGLOW_NETD_GENERATED_UNIX_MS={}\n",
        snapshot.interfaces.len(),
        up_count,
        default,
        snapshot.generated_unix_ms
    )
}

pub fn write_snapshot(
    snapshot: &NetworkSnapshot,
    state_json: impl AsRef<Path>,
    runtime_env: impl AsRef<Path>,
) -> io::Result<()> {
    let json = render_json(snapshot);
    write_file(state_json.as_ref(), json.as_bytes())?;
    write_file(
        runtime_env.as_ref(),
        render_runtime_env(snapshot).as_bytes(),
    )
}

fn read_interface(name: &str, path: &Path) -> io::Result<NetworkInterface> {
    Ok(NetworkInterface {
        name: name.to_owned(),
        index: read_trimmed(path.join("ifindex"))?.and_then(|value| value.parse().ok()),
        kind: read_kind(path)?,
        mac_address: read_trimmed(path.join("address"))?,
        operstate: read_operstate(path)?,
        mtu: read_trimmed(path.join("mtu"))?.and_then(|value| value.parse().ok()),
        carrier: read_trimmed(path.join("carrier"))?.and_then(|value| match value.as_str() {
            "0" => Some(false),
            "1" => Some(true),
            _ => None,
        }),
        speed_mbps: read_trimmed(path.join("speed"))?.and_then(|value| value.parse().ok()),
        rx_bytes: read_trimmed(path.join("statistics/rx_bytes"))?
            .and_then(|value| value.parse().ok()),
        tx_bytes: read_trimmed(path.join("statistics/tx_bytes"))?
            .and_then(|value| value.parse().ok()),
        flags_hex: read_trimmed(path.join("flags"))?,
    })
}

fn read_kind(path: &Path) -> io::Result<InterfaceKind> {
    if path.join("wireless").is_dir() {
        return Ok(InterfaceKind::Wireless);
    }
    let Some(value) = read_trimmed(path.join("type"))? else {
        return Ok(InterfaceKind::Unknown);
    };
    Ok(match value.parse::<i32>() {
        Ok(1) => InterfaceKind::Ethernet,
        Ok(772) => InterfaceKind::Loopback,
        Ok(kind) => InterfaceKind::Other(kind),
        Err(_) => InterfaceKind::Unknown,
    })
}

fn read_operstate(path: &Path) -> io::Result<OperState> {
    Ok(
        match read_trimmed(path.join("operstate"))?
            .as_deref()
            .unwrap_or("unknown")
        {
            "up" => OperState::Up,
            "down" => OperState::Down,
            "dormant" => OperState::Dormant,
            "lowerlayerdown" => OperState::LowerLayerDown,
            "notpresent" => OperState::NotPresent,
            "testing" => OperState::Testing,
            _ => OperState::Unknown,
        },
    )
}

fn read_trimmed(path: PathBuf) -> io::Result<Option<String>> {
    match fs::read_to_string(&path) {
        Ok(value) => Ok(Some(value.trim().to_owned())),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

fn write_file(path: &Path, contents: &[u8]) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, contents)
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_sys_class_net_fixture() {
        let fixture = TestSysfs::new();
        fixture.interface(
            "eth0",
            &[
                ("ifindex", "2\n"),
                ("type", "1\n"),
                ("address", "02:00:00:00:00:01\n"),
                ("operstate", "up\n"),
                ("mtu", "1500\n"),
                ("carrier", "1\n"),
                ("speed", "1000\n"),
                ("statistics/rx_bytes", "42\n"),
                ("statistics/tx_bytes", "84\n"),
                ("flags", "0x1003\n"),
            ],
        );
        fixture.interface(
            "lo",
            &[
                ("ifindex", "1\n"),
                ("type", "772\n"),
                ("operstate", "unknown\n"),
                ("mtu", "65536\n"),
                ("statistics/rx_bytes", "7\n"),
                ("statistics/tx_bytes", "9\n"),
            ],
        );

        let snapshot = read_snapshot(fixture.path()).expect("snapshot should parse");

        assert_eq!(snapshot.interfaces.len(), 2);
        assert_eq!(snapshot.interfaces[0].name, "eth0");
        assert_eq!(snapshot.interfaces[0].kind, InterfaceKind::Ethernet);
        assert_eq!(snapshot.interfaces[0].operstate, OperState::Up);
        assert_eq!(snapshot.interfaces[0].carrier, Some(true));
        assert_eq!(snapshot.interfaces[0].rx_bytes, Some(42));
        assert_eq!(snapshot.interfaces[1].kind, InterfaceKind::Loopback);
    }

    #[test]
    fn renders_runtime_state_for_shell_consumers() {
        let snapshot = NetworkSnapshot {
            generated_unix_ms: 123,
            interfaces: vec![
                NetworkInterface {
                    name: "lo".to_owned(),
                    index: Some(1),
                    kind: InterfaceKind::Loopback,
                    mac_address: None,
                    operstate: OperState::Up,
                    mtu: Some(65536),
                    carrier: None,
                    speed_mbps: None,
                    rx_bytes: Some(1),
                    tx_bytes: Some(2),
                    flags_hex: None,
                },
                NetworkInterface {
                    name: "eth0".to_owned(),
                    index: Some(2),
                    kind: InterfaceKind::Ethernet,
                    mac_address: Some("02:00:00:00:00:01".to_owned()),
                    operstate: OperState::Up,
                    mtu: Some(1500),
                    carrier: Some(true),
                    speed_mbps: Some(1000),
                    rx_bytes: Some(3),
                    tx_bytes: Some(4),
                    flags_hex: Some("0x1003".to_owned()),
                },
            ],
        };

        assert_eq!(
            render_runtime_env(&snapshot),
            "ALPENGLOW_NETD_INTERFACES=2\nALPENGLOW_NETD_UP_INTERFACES=2\nALPENGLOW_NETD_DEFAULT_INTERFACE=eth0\nALPENGLOW_NETD_GENERATED_UNIX_MS=123\n"
        );
    }

    #[test]
    fn renders_json_with_kebab_case() {
        let snapshot = NetworkSnapshot {
            generated_unix_ms: 123,
            interfaces: vec![NetworkInterface {
                name: "eth0".to_owned(),
                index: Some(2),
                kind: InterfaceKind::Ethernet,
                mac_address: Some("02:00:00:00:00:01".to_owned()),
                operstate: OperState::Up,
                mtu: Some(1500),
                carrier: Some(true),
                speed_mbps: Some(1000),
                rx_bytes: Some(42),
                tx_bytes: Some(84),
                flags_hex: Some("0x1003".to_owned()),
            }],
        };
        let json = render_json(&snapshot);
        assert!(json.contains("\"name\": \"eth0\""));
        assert!(json.contains("\"kind\": \"ethernet\""));
        assert!(json.contains("\"mac-address\": \"02:00:00:00:00:01\""));
        assert!(json.contains("\"carrier\": true"));
        assert!(json.contains("\"generated_unix_ms\": 123"));
        assert!(json.contains("\"interfaces\": ["));
    }

    struct TestSysfs {
        path: PathBuf,
    }

    impl TestSysfs {
        fn new() -> Self {
            let mut path = std::env::temp_dir();
            path.push(format!(
                "alpenglow-netd-test-{}-{}",
                std::process::id(),
                now_unix_ms()
            ));
            fs::create_dir_all(&path).expect("fixture root should be created");
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }

        fn interface(&self, name: &str, files: &[(&str, &str)]) {
            let interface = self.path.join(name);
            fs::create_dir_all(&interface).expect("interface dir should be created");
            for (relative, contents) in files {
                let path = interface.join(relative);
                if let Some(parent) = path.parent() {
                    fs::create_dir_all(parent).expect("fixture parent should be created");
                }
                fs::write(path, contents).expect("fixture file should be written");
            }
        }
    }

    impl Drop for TestSysfs {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}

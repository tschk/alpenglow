//! Which whole disks must not be installed onto: the ones holding mounted filesystems (this
//! includes the disk the system booted from) and the one holding the installer image.
//!
//! Pure parsing and mapping live here so they can be tested with fixture text; the real
//! mapping from a block device to the whole disks behind it reads sysfs.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MountEntry {
    pub mount_point: String,
    pub source: String,
}

/// Why a disk cannot be chosen.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InUse {
    Mounted(String),
    HoldsImage,
}

impl InUse {
    pub fn label(&self) -> String {
        match self {
            InUse::Mounted(at) => format!("In use, mounted at {at}"),
            InUse::HoldsImage => "Holds the installer image".to_string(),
        }
    }
}

/// `\040`-style escapes mountinfo uses for spaces and other special characters.
fn unescape(field: &str) -> String {
    let bytes = field.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\'
            && i + 4 <= bytes.len()
            && bytes[i + 1..i + 4].iter().all(u8::is_ascii_digit)
        {
            if let Ok(value) = u8::from_str_radix(&field[i + 1..i + 4], 8) {
                out.push(value);
                i += 4;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Entries of /proc/self/mountinfo. Pseudo filesystems stay in: the mount holding the image is
/// the longest matching mount point, and that may well be a tmpfs.
pub fn parse_mountinfo(text: &str) -> Vec<MountEntry> {
    text.lines()
        .filter_map(|line| {
            let (left, right) = line.split_once(" - ")?;
            let mount_point = unescape(left.split_whitespace().nth(4)?);
            let source = unescape(right.split_whitespace().nth(1)?);
            Some(MountEntry {
                mount_point,
                source,
            })
        })
        .collect()
}

/// Whole-disk names (e.g. `vda`) that must not be written, with the reason. `resolve` maps a
/// `/dev/...` source to the whole disks behind it (partitions, device-mapper, ...).
pub fn blocked_disks(
    mounts: &[MountEntry],
    image: &Path,
    resolve: &dyn Fn(&str) -> Vec<String>,
) -> BTreeMap<String, InUse> {
    let mut blocked = BTreeMap::new();
    // bcachefs and btrfs report several devices as `/dev/a:/dev/b`.
    let resolve_all = |source: &str| -> Vec<String> {
        source
            .split(':')
            .filter(|device| device.starts_with("/dev/"))
            .flat_map(resolve)
            .collect()
    };
    for mount in mounts {
        for disk in resolve_all(&mount.source) {
            blocked
                .entry(disk)
                .or_insert_with(|| InUse::Mounted(mount.mount_point.clone()));
        }
    }
    // The mount that contains the image is the longest mount point that prefixes its path.
    let holder = mounts
        .iter()
        .filter(|mount| image.starts_with(&mount.mount_point))
        .max_by_key(|mount| mount.mount_point.len());
    if let Some(holder) = holder {
        for disk in resolve_all(&holder.source) {
            // A disk that is also mounted elsewhere keeps the more specific "holds image".
            blocked.insert(disk, InUse::HoldsImage);
        }
    }
    blocked
}

/// Whole disks backing `/dev/<name>`: the parent of a partition, or the device itself, following
/// device-mapper/RAID `slaves`.
fn sysfs_disks_of(name: &str, sys_class_block: &Path, depth: usize) -> Vec<String> {
    if depth > 8 {
        return Vec::new();
    }
    let node = sys_class_block.join(name);
    let Ok(real) = fs::canonicalize(&node) else {
        return Vec::new();
    };
    let mut disks = Vec::new();
    if real.join("partition").exists() {
        if let Some(parent) = real
            .parent()
            .and_then(|parent| parent.file_name())
            .and_then(|parent| parent.to_str())
        {
            disks.push(parent.to_string());
        }
    } else if let Some(own) = real.file_name().and_then(|own| own.to_str()) {
        disks.push(own.to_string());
    }
    if let Ok(slaves) = fs::read_dir(real.join("slaves")) {
        for slave in slaves.flatten() {
            if let Some(slave) = slave.file_name().to_str() {
                disks.extend(sysfs_disks_of(slave, sys_class_block, depth + 1));
            }
        }
    }
    disks.sort();
    disks.dedup();
    disks
}

/// Resolves a `/dev/...` source (following symlinks such as /dev/mapper/*) to whole disks.
pub fn resolve_with_sysfs(source: &str, sys_class_block: &Path) -> Vec<String> {
    let Ok(node) = fs::canonicalize(source) else {
        return Vec::new();
    };
    let Some(name) = node.file_name().and_then(|name| name.to_str()) else {
        return Vec::new();
    };
    sysfs_disks_of(name, sys_class_block, 0)
}

/// Disks currently in use on this machine, keyed by whole-disk name.
pub fn disks_in_use(image: &Path) -> BTreeMap<String, InUse> {
    let text = fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let sys = PathBuf::from("/sys/class/block");
    let image = fs::canonicalize(image).unwrap_or_else(|_| image.to_path_buf());
    blocked_disks(&parse_mountinfo(&text), &image, &|source| {
        resolve_with_sysfs(source, &sys)
    })
}

/// The whole-disk name for a target path like `/dev/vda` (`vda`), if it is one.
pub fn disk_name(target: &Path) -> Option<String> {
    let real = fs::canonicalize(target).unwrap_or_else(|_| target.to_path_buf());
    real.file_name()
        .and_then(|name| name.to_str())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    use tempfile::tempdir;

    const MOUNTINFO: &str = "\
22 28 0:21 / /sys rw,nosuid,nodev,noexec,relatime shared:7 - sysfs sysfs rw
28 1 254:2 / / rw,relatime shared:1 - ext4 /dev/vda2 rw,errors=remount-ro
30 28 0:25 / /run rw,nosuid,nodev shared:5 - tmpfs tmpfs rw,mode=755
41 28 8:17 / /media/usb\\040stick rw,relatime shared:9 - vfat /dev/sdb1 rw
44 28 0:40 / /srv/data rw,relatime - bcachefs /dev/vdc:/dev/vdd rw
";

    fn fake_resolver(source: &str) -> Vec<String> {
        match source {
            "/dev/vda2" => vec!["vda".into()],
            "/dev/sdb1" => vec!["sdb".into()],
            "/dev/vdc" => vec!["vdc".into()],
            "/dev/vdd" => vec!["vdd".into()],
            _ => Vec::new(),
        }
    }

    #[test]
    fn mountinfo_lists_every_mount_and_unescapes() {
        let mounts = parse_mountinfo(MOUNTINFO);
        let points: Vec<_> = mounts.iter().map(|m| m.mount_point.as_str()).collect();
        assert_eq!(
            points,
            ["/sys", "/", "/run", "/media/usb stick", "/srv/data"]
        );
        assert_eq!(mounts[1].source, "/dev/vda2");
        assert_eq!(mounts[2].source, "tmpfs");
    }

    #[test]
    fn mounted_disks_are_blocked_with_their_mount_point() {
        let mounts = parse_mountinfo(MOUNTINFO);
        let blocked = blocked_disks(
            &mounts,
            Path::new("/run/alpenglow/a.img.zst"),
            &fake_resolver,
        );
        assert_eq!(blocked.get("vda"), Some(&InUse::Mounted("/".to_string())));
        assert_eq!(
            blocked.get("sdb"),
            Some(&InUse::Mounted("/media/usb stick".to_string()))
        );
        assert!(!blocked.contains_key("vdb"));
        // Both members of a multi-device filesystem are in use.
        assert_eq!(
            blocked.get("vdc"),
            Some(&InUse::Mounted("/srv/data".to_string()))
        );
        assert_eq!(
            blocked.get("vdd"),
            Some(&InUse::Mounted("/srv/data".to_string()))
        );
    }

    #[test]
    fn the_disk_holding_the_image_is_marked_as_such() {
        let mounts = parse_mountinfo(MOUNTINFO);
        let image = Path::new("/media/usb stick/alpenglow.img.zst");
        let blocked = blocked_disks(&mounts, image, &fake_resolver);
        assert_eq!(blocked.get("sdb"), Some(&InUse::HoldsImage));
        // The root disk is still blocked, for being mounted.
        assert_eq!(blocked.get("vda"), Some(&InUse::Mounted("/".to_string())));
    }

    #[test]
    fn image_on_a_tmpfs_does_not_block_the_disk_backing_root() {
        let mounts = parse_mountinfo(MOUNTINFO);
        // /run is a tmpfs, a longer match than "/": the image lives in RAM, not on vda.
        let blocked = blocked_disks(
            &mounts,
            Path::new("/run/alpenglow/a.img.zst"),
            &fake_resolver,
        );
        assert_eq!(blocked.get("vda"), Some(&InUse::Mounted("/".to_string())));
        assert!(blocked.values().all(|reason| *reason != InUse::HoldsImage));
        assert_eq!(blocked.len(), 4);
    }

    #[test]
    fn image_directly_on_the_root_disk_marks_it_as_holding_the_image() {
        let mounts = parse_mountinfo(MOUNTINFO);
        let blocked = blocked_disks(&mounts, Path::new("/home/me/a.img"), &fake_resolver);
        assert_eq!(blocked.get("vda"), Some(&InUse::HoldsImage));
    }

    #[test]
    fn relative_pseudo_sources_are_never_resolved() {
        let mounts = parse_mountinfo("30 28 0:25 / /run rw - tmpfs tmpfs rw\n");
        let seen = std::cell::RefCell::new(Vec::new());
        let blocked = blocked_disks(&mounts, Path::new("/run/x"), &|source| {
            seen.borrow_mut().push(source.to_string());
            Vec::new()
        });
        assert!(blocked.is_empty());
        assert!(seen.borrow().is_empty(), "resolved {:?}", seen.borrow());
    }

    #[test]
    fn labels_are_readable() {
        assert_eq!(InUse::HoldsImage.label(), "Holds the installer image");
        assert_eq!(InUse::Mounted("/".into()).label(), "In use, mounted at /");
    }

    #[test]
    fn sysfs_resolution_maps_partitions_and_slaves_to_whole_disks() {
        let dir = tempdir().unwrap();
        let sys = dir.path().join("sys");
        let devices = dir.path().join("devices");
        let class = sys.join("class/block");
        fs::create_dir_all(&class).unwrap();
        // vda with a partition vda2, and a mapper device dm-0 stacked on vdb1.
        let vda = devices.join("block/vda");
        let vda2 = vda.join("vda2");
        fs::create_dir_all(&vda2).unwrap();
        fs::write(vda2.join("partition"), "2").unwrap();
        let vdb = devices.join("block/vdb");
        let vdb1 = vdb.join("vdb1");
        fs::create_dir_all(&vdb1).unwrap();
        fs::write(vdb1.join("partition"), "1").unwrap();
        let dm = devices.join("block/dm-0");
        fs::create_dir_all(dm.join("slaves")).unwrap();
        symlink(&vdb1, dm.join("slaves/vdb1")).unwrap();
        symlink(&vda, class.join("vda")).unwrap();
        symlink(&vda2, class.join("vda2")).unwrap();
        symlink(&vdb1, class.join("vdb1")).unwrap();
        symlink(&dm, class.join("dm-0")).unwrap();

        // The /dev nodes, including a mapper-style symlink.
        let dev = dir.path().join("dev");
        fs::create_dir_all(dev.join("mapper")).unwrap();
        for node in ["vda", "vda2", "vdb1", "dm-0"] {
            fs::write(dev.join(node), "").unwrap();
        }
        symlink(dev.join("dm-0"), dev.join("mapper/vg-root")).unwrap();

        let resolve = |node: &str| resolve_with_sysfs(node, &class);
        assert_eq!(resolve(dev.join("vda").to_str().unwrap()), ["vda"]);
        assert_eq!(resolve(dev.join("vda2").to_str().unwrap()), ["vda"]);
        // A device-mapper node resolves through its slaves to the disk underneath.
        let mapped = resolve(dev.join("mapper/vg-root").to_str().unwrap());
        assert!(mapped.contains(&"vdb".to_string()), "got {mapped:?}");
        assert!(resolve("/nonexistent/dev").is_empty());
    }
}

//! Opt-in read-only bcachefs snapshot of /state before each Oil transaction.
//!
//! Off unless `/etc/alpenglow/state-snapshots` exists (written at image build
//! for editions with `state_snapshots = 1`) or `OIL_STATE_SNAPSHOTS=1`.
//! `OIL_STATE_SNAPSHOTS=0` forces it off. When off, the cost is one stat().
//! A failed snapshot warns and does not block the transaction: diskless boots
//! have no /state to snapshot.

use std::path::Path;

const MARKER: &str = "/etc/alpenglow/state-snapshots";
const STATE_ROOT: &str = "/state";
const KEEP: usize = 10;

fn enabled() -> bool {
    match std::env::var("OIL_STATE_SNAPSHOTS").as_deref() {
        Ok("1") => true,
        Ok("0") => false,
        _ => Path::new(MARKER).exists(),
    }
}

/// Take a snapshot of /state labelled with `op` if snapshots are enabled.
pub fn before_transaction(op: &str) {
    if !enabled() {
        return;
    }
    match imp::snapshot(Path::new(STATE_ROOT), op, KEEP) {
        Ok(path) => eprintln!("Snapshot {}", path.display()),
        Err(e) => eprintln!("warning: /state snapshot skipped: {e}"),
    }
}

#[cfg(target_os = "linux")]
mod imp {
    const SNAPSHOT_DIR: &str = ".snapshots";
    const PREFIX: &str = "oil-";
    use std::ffi::CString;
    use std::io;
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::io::AsRawFd;
    use std::path::{Path, PathBuf};

    // struct bch_ioctl_subvolume from bcachefs_ioctl.h
    #[repr(C)]
    struct BchIoctlSubvolume {
        flags: u32,
        dirfd: u32,
        mode: u16,
        pad: [u16; 3],
        dst_ptr: u64,
        src_ptr: u64,
    }
    // _IOW(0xbc, 16|17, struct bch_ioctl_subvolume)
    const BCH_IOCTL_SUBVOLUME_CREATE: libc::c_ulong = 0x4020_bc10;
    const BCH_IOCTL_SUBVOLUME_DESTROY: libc::c_ulong = 0x4020_bc11;
    const BCH_SUBVOL_SNAPSHOT_CREATE: u32 = 1 << 0;
    const BCH_SUBVOL_SNAPSHOT_RO: u32 = 1 << 1;

    fn cpath(p: &Path) -> io::Result<CString> {
        CString::new(p.as_os_str().as_bytes())
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path contains NUL"))
    }

    fn subvol_ioctl(
        root: &Path,
        req: libc::c_ulong,
        flags: u32,
        dst: &Path,
        src: Option<&Path>,
    ) -> io::Result<()> {
        let fd = std::fs::File::open(root)?;
        let dst = cpath(dst)?;
        let src = src.map(cpath).transpose()?;
        let arg = BchIoctlSubvolume {
            flags,
            dirfd: libc::AT_FDCWD as u32,
            mode: 0,
            pad: [0; 3],
            dst_ptr: dst.as_ptr() as u64,
            src_ptr: src.as_ref().map_or(0, |s| s.as_ptr() as u64),
        };
        // SAFETY: arg and the C strings it points to outlive the call.
        let r = unsafe { libc::ioctl(fd.as_raw_fd(), req as _, &arg) };
        if r < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    pub fn snapshot(root: &Path, op: &str, keep: usize) -> io::Result<PathBuf> {
        let dir = root.join(SNAPSHOT_DIR);
        std::fs::create_dir_all(&dir)?;
        let millis = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);
        let dst = dir.join(format!("{PREFIX}{millis:013}-{op}"));
        subvol_ioctl(
            root,
            BCH_IOCTL_SUBVOLUME_CREATE,
            BCH_SUBVOL_SNAPSHOT_CREATE | BCH_SUBVOL_SNAPSHOT_RO,
            &dst,
            Some(root),
        )
        .map_err(|e| io::Error::new(e.kind(), format!("{}: {e}", dst.display())))?;
        prune(root, &dir, keep);
        Ok(dst)
    }

    /// Keep the newest `keep` Oil snapshots; names sort by creation time.
    fn prune(root: &Path, dir: &Path, keep: usize) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        let mut snaps: Vec<PathBuf> = entries
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().as_bytes().starts_with(PREFIX.as_bytes()))
            .map(|e| e.path())
            .collect();
        snaps.sort();
        let excess = snaps.len().saturating_sub(keep);
        for old in &snaps[..excess] {
            if let Err(e) = subvol_ioctl(root, BCH_IOCTL_SUBVOLUME_DESTROY, 0, old, None) {
                eprintln!("warning: could not delete snapshot {}: {e}", old.display());
            }
        }
    }
}

#[cfg(not(target_os = "linux"))]
mod imp {
    use std::io;
    use std::path::{Path, PathBuf};

    pub fn snapshot(_root: &Path, _op: &str, _keep: usize) -> io::Result<PathBuf> {
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "bcachefs snapshots need Linux",
        ))
    }
}

//! Verification must read the device, not the page cache of what was just written. Needs root
//! and losetup, so it skips (and passes) elsewhere; CI runs it under sudo.

use alpenglow_installer::wizard::is_root;
use alpenglow_installer::{install_image_verified, verify_written};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::PathBuf;
use std::process::Command;

struct LoopDevice(PathBuf);

impl LoopDevice {
    fn attach(backing: &std::path::Path) -> Option<Self> {
        let output = Command::new("losetup")
            .args(["-f", "--show"])
            .arg(backing)
            .output()
            .ok()?;
        output.status.success().then(|| {
            Self(PathBuf::from(
                String::from_utf8_lossy(&output.stdout).trim().to_string(),
            ))
        })
    }
}

impl Drop for LoopDevice {
    fn drop(&mut self) {
        let _ = Command::new("losetup").arg("-d").arg(&self.0).status();
    }
}

#[test]
fn verification_notices_corruption_on_the_device_behind_the_page_cache() {
    if !is_root() {
        eprintln!("skipping: needs root");
        return;
    }
    let dir = tempfile::tempdir().unwrap();
    let backing = dir.path().join("backing.img");
    fs::write(&backing, vec![0u8; 16 * 1024 * 1024]).unwrap();
    let Some(device) = LoopDevice::attach(&backing) else {
        eprintln!("skipping: losetup unavailable");
        return;
    };

    // udev/blkid often keep a block device open; the kernel then keeps its page cache across our
    // writer closing, so a read-back would see what we wrote rather than what the media holds.
    let _holder = File::open(&device.0).unwrap();

    let data: Vec<u8> = (0..8 * 1024 * 1024).map(|i| (i % 251) as u8).collect();
    let source = dir.path().join("source.img");
    fs::write(&source, &data).unwrap();
    install_image_verified(&source, &device.0, false, |_| {}).unwrap();

    // Flip one byte of the backing store without going through the loop device.
    let offset = 5 * 1024 * 1024;
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&backing)
        .unwrap();
    file.seek(SeekFrom::Start(offset)).unwrap();
    let mut byte = [0u8; 1];
    file.read_exact(&mut byte).unwrap();
    file.seek(SeekFrom::Start(offset)).unwrap();
    file.write_all(&[byte[0] ^ 0xFF]).unwrap();
    file.sync_all().unwrap();

    let digest = Sha256::digest(&data);
    let err = verify_written(&device.0, data.len() as u64, &digest, |_| {}).unwrap_err();
    assert!(err.to_string().contains("differs from the image"), "{err}");
}

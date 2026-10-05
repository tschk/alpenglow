# Installer (desktop base)

`alpenglow-install-gui` writes the Alpenglow disk image (`.img` or `.img.zst`) to a disk. It is
built with [crepuscularity](https://github.com/tschk/crepuscularity) (`view!` templates on
gpui-ce) and follows Calamares' page flow, trimmed to what an image-based installer can do:

| Page | What it does |
|------|--------------|
| Welcome | Requirement checks: image readable, disks present, running as root |
| Disk | Pick the target; disks in use are shown with the reason and cannot be chosen |
| Summary | Image, disk and the erase warning; Install stays disabled until the erase is confirmed |
| Install | Writes, then reads the disk back and checks it, with live progress |
| Finish | Result, and Restart |

Back and Quit are hidden while the image is being written.

The look is the repo's near-black mono theme with a slight Dracula accent.

## Safety

- **In-use disks are refused.** `/proc/self/mountinfo` is resolved to whole disks through sysfs
  (partitions, device-mapper/RAID, multi-device filesystems). Any disk with a mounted filesystem
  is blocked, and so is the disk holding the installer image. The check runs again right before
  writing.
- **The write is verified.** The image is hashed (SHA-256) while it is written, then the disk is
  re-read and compared. The page cache is dropped first (`posix_fadvise(DONTNEED)`, and
  `BLKFLSBUF` on block devices): udev/blkid often keep a device open, and then a naive read-back
  returns what was just written rather than what the media holds. `tests/loop_verify.rs` proves
  this on a real loop device and fails if the cache drop is removed.
- **The backup GPT is moved to the end of the disk** (`gpt.rs`, the same fix as `sgdisk -e`). It
  acts only on a fully valid table, never touches partitions, never overlaps the image, and
  skips anything it cannot do safely (damaged table, 4K-sector disks). Cross-checked against
  `sgdisk -v` and `sgdisk -e`.
- **"Done" means on the device**: the writer flushes and `fsync`s.

## Not in the base installer

Locale and keyboard pages are not planned for now. The **users** page and **partitioning** belong
to the desktop-full installer, and will be implemented directly in Rust (no blivet/libblockdev
dependency, to keep the live image lean).

## Testing without risking a disk

Never test against a real disk. Use a loop device on a scratch file:

```sh
truncate -s 300M disk.img && LOOP=$(sudo losetup -f --show disk.img)
alpenglow-install-gui image.img.zst "$LOOP"      # preselects the loop device
sudo sgdisk -v "$LOOP"                           # "No problems found"
sudo losetup -d "$LOOP"
```

CI: `installer-gui` (build, tests, the loop-device verification test, live-root library
coverage), `installer-gui-aarch64` (musl build and a headless-compositor smoke), and
`installer-gui-aarch64-qemu` (boots the aarch64 desktop kernel and runs the GUI).

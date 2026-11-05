# v0.1.722 release readiness

**Do not cut the corrected release yet.** The working x86 image was assembled in an orb using an experimental FUSE FAT mount, not on a normal release host. FUSE FAT assembly has not been verified for release reproducibility. The published v0.1.721 assets have not been replaced. See the [v0.1.721 boot audit](release-v0.1.721-boot-audit.md) for the erratum and evidence.

## What has been proven

A fresh x86 disk with a newly built kernel and initramfs and real bcachefs state booted in QEMU under both SeaBIOS and OVMF. Each reached a root shell and mounted `/state` read-write. Using a disposable persistent overlay, each wrote a marker and recovered it after a forced guest reset. `scripts/test-release-x86-boot.sh` performs these boot, mount, and persistence checks on the compressed disk asset.

`scripts/check-compressed-initramfs.sh` extracts the initramfs from the compressed disk and compares its size and SHA-256 with the build input. It rejected the observed corrupt image and accepted the image used for the passing boot test.

## Before publishing

Build the corrected release on a normal release host without the experimental FUSE FAT assembly. Pass every applicable release gate, including the compressed-content comparison. Run the SeaBIOS and OVMF boot and persistence tests on the resulting compressed x86 disk assets. Do not treat the orb build or a passing build of another artifact as proof for the assets to publish.

## What the gates check

- `scripts/check-release-architecture.py` checks the advertised architecture and checks disk images for an EFI System Partition and BIOS bootloader markers.
- Native rootfs assembly checks executable commands for enabled boot services and their dependencies. It can omit unavailable optional services; it does not inspect every inline command or dynamic library.
- The native initramfs build checks shell syntax for shipped shebang-bearing shell scripts and probes selected shell features. It does not prove every script's runtime behavior.
- `scripts/check-compressed-initramfs.sh` checks the initramfs content inside each compressed x86 disk. It does not verify every file in the disk.
- `scripts/test-release-x86-boot.sh` boots each compressed x86 disk under both firmware types and checks the root shell, writable bcachefs state, and persistence across a forced reset before upload.

## Still unverified

Graceful shutdown, physical hardware, and aarch64 release paths beyond the desktop path remain unverified. The aarch64 desktop QEMU checks also do not establish physical-hardware support. The cause of the corrupt compressed copy remains unknown: the evidence does not distinguish FUSE behavior, write visibility, or a concurrent write.

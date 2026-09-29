# Architecture Support

## x86_64 — main branch (primary target)

QEMU: `qemu-system-x86_64 -machine q35,accel=kvm|hvf`  
Kernel: custom kernel.org latest stable + CONFIG_RUST=y, or Alpine pre-built virt  
Boot: `scripts/boot-native.sh` (build + QEMU boot)  
UEFI: OVMF (saves ~200ms vs SeaBIOS)  
Init: dinit + toybox + getty. Public SKUs and 2026-08-25 measurements: [editions-and-roles.md](editions-and-roles.md). Historical ultramarine KVM (2026-07, not SKU names): ~1.3s `BUILD_PROFILE=standard`, ~0.6s `FAST=1` Zig init.

## riscv64 — main

QEMU: `qemu-system-riscv64 -M virt -bios opensbi`  
Userspace: `scripts/build-riscv64.sh` cross-compiles the Zig init and alpenglow-ctl for `riscv64-linux-musl` and packs an initramfs.  
Kernel: not built in-tree. Stage one with `ALPENGLOW_RISCV64_KERNEL=/path/to/Image`.  
Boot: `scripts/qemu-boot-riscv64.sh`  
Console: `earlycon=sbi console=ttyS0,115200`

## aarch64 — main

QEMU: `qemu-system-aarch64 -M virt -cpu max`  
Userspace: `scripts/build-aarch64.sh` (Zig init + alpenglow-ctl). Full rootfs: `scripts/build-aarch64-fast.sh` (needs Docker).  
Kernel: stage one with `ALPENGLOW_AARCH64_KERNEL=/path/to/Image`.  
Boot: `scripts/qemu-boot-aarch64.sh`

## legacy (i686) — main

`scripts/build-legacy-initramfs.sh` rebuilds the shipped v86 rootfs with busybox ash instead of bash. Bash and fastfetch in that image use SSE2 and die with SIGILL below a Pentium 4; busybox does not. The kernel is unchanged, so it still requires an i686.

Boot: `scripts/bench-legacy.sh` times power-on to the banner.

Measured 2026-09-29 on an Apple M5 Pro, QEMU 11.0.2 TCG (no HVF in this qemu-system-i386 build), 1s resolution:

| Machine | Result |
|---------|--------|
| pc + `-cpu 486` | refused: kernel wants an i686 |
| pc + `-cpu pentium` | refused: kernel wants an i686 |
| pc + `-cpu pentium2`, 96 MiB | banner at 22s |
| pc + `-cpu pentium2`, 64 MiB | banner at 2s (warm host) |
| pc + `-cpu pentium2`, 32 MiB | panics: initrd unpacks over the RAM disk |
| pc + `-cpu pentium3`, 128 MiB | banner at 18s |
| ppc `g3beige` | kernel not built here; `scripts/build-legacy-kernels.sh ppc` |
| arm `versatilepb` (armv5 stand-in for the iPAQ) | kernel not built here; `scripts/build-legacy-kernels.sh armv5` |

The Zig init now builds for 32-bit targets. `build/legacy/init-powerpc` (8.5K, PowerPC) and `build/legacy/init-armv5` (8.6K, ARM EABI) are static musl binaries, packed as `initramfs-powerpc.cpio.gz` and `initramfs-armv5.cpio.gz`. They need the kernels above to boot. Building those kernels needs the linux-7.1.3 tarball and Docker; the kernel.org download did not finish on this link.

## armv5 (iPAQ-class)

The Compaq iPAQ H3600 is a StrongARM SA-1110 board, and QEMU has no H3600 machine. `collie` is the SA-1110 machine, but mainline Linux no longer boots on it. `versatilepb` is the armv5 machine a current kernel can boot, so `system/backends/legacy/armv5.fragment` targets that. It is a stand-in for measuring an armv5 boot, not an iPAQ port.

## Rockchip RK3566 — main

U-Boot: `scripts/build-uboot-rk3566.sh` (`BOARD=quartz64-a|quartz64-b|soquartz-model-a|orangepi-3b`, needs Docker or an aarch64 cross toolchain plus the rkbin DDR blobs)  
Kernel + userspace: `scripts/cross-build.sh aarch64-linux-musl` (needs Docker; merges `system/backends/rk3566/kernel-rockchip-rk3566.config`)  
Flash: `scripts/flash-rk3566.sh <device>` (writes a raw block device; refuses unexpected device names)  
Boot scripts: `system/backends/rk3566/boot.cmd`, `system/backends/rk3566/boot-orangepi-3b.cmd`  
Test notes: `scripts/test-rk3566.md`

# Architecture Support

Target: diskless, hardened, immutable Linux appliance across architectures.

## Current (x86_64)

- Boot: Limine (UEFI) + SeaBIOS (QEMU)
- Kernel: Linux 7.0, CONFIG_RUST=y, defconfig+kvm_guest+rust
- Init: dinit (Zig 4.8KB init as fallback)
- Userland: toybox musl static
- Toolchain: LLVM/Clang, Zig 0.16, Rust 1.93
- CI: GitHub Actions ubuntu-latest, cross-target via Zig

## Target: aarch64 (Rockchip RK3566)

### Status
- Mainline Linux 7.0 supports aarch64 with CONFIG_RUST=y
- Rockchip RK3566 is supported in mainline since Linux 6.12 (drivers: rk3x-i2c, dw-mmc, dwmac, phy-rockchip-inno-usb2, etc.)
- Chimera Linux supports aarch64 (musl + LLVM)

### Kernel Config
```
CONFIG_ARCH_ROCKCHIP=y
CONFIG_MACH_RK3568=y
CONFIG_ARM64=y
CONFIG_ARM64_VA_BITS_48=y
CONFIG_NR_CPUS=4
CONFIG_PREEMPT_NONE=y
CONFIG_RUST=y
```

### Boot
- U-Boot 2025.04: SPL + TF-A + U-Boot proper
- Extlinux/ext4 on SD/eMMC
- Limine has aarch64 support (not well tested)

### Required DTBs
- `rk3566-quartz64-a.dtb` (PINE64 Quartz64 Model A)
- `rk3566-soquartz.dtb` (PINE64 SOQuartz)
- `rk3566-roc-pc.dtb` (Firefly ROC-RK3566-PC)

### Alpine-like Rootfs Creation
```
qemu-system-aarch64 -machine virt -cpu cortex-a57 -smp 2 -m 512 \
  -kernel arch/arm64/boot/Image -initrd initramfs.cpio.zst \
  -append "quiet console=ttyAMA0"
```

### Cross-build Toolchain
```
# Zig (works out of box):
zig build -Dtarget=aarch64-linux-musl

# Rust:
rustup target add aarch64-unknown-linux-musl
cargo build --target aarch64-unknown-linux-musl

# Kernel:
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-musl- defconfig
```

### Alpenglow Porting
- [x] Kernel: aarch64 defconfig + rockchip + rust
- [x] Initramfs: aarch64 static binaries (Zig cross-compiles)
- [x] Zig components: init, kernelctl, glowfsctl for aarch64-linux-musl
- [x] Toybox: CROSS_COMPILE=aarch64-linux-musl- (via musl-cross-make)
- [ ] Dinit: CXX=aarch64-linux-musl-g++
- [x] Boot: U-Boot script or Limine aarch64
- [ ] Devices: UART, SD/eMMC, Ethernet, USB
- [x] Testing: QEMU virt (verified boot to Zig init: 0.5s to reboot)

### Quick Start (aarch64)
```sh
# Cross-compile Zig components + build initramfs + boot in QEMU
scripts/build-aarch64.sh

# Boot test
scripts/qemu-boot-aarch64.sh
```

## Target: riscv64

### Status
- Mainline Linux 7.0 supports riscv64 with CONFIG_RUST=y (since Linux 6.1)
- Chimera Linux supports riscv64
- RISC-V ISO: https://chimera-linux.org/download/riscv64/

### Kernel Config
```
CONFIG_ARCH_RV64I=y
CONFIG_RISCV_SBI=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_RUST=y
```

### Boot
- OpenSBI + U-Boot
- QEMU virt machine (-machine virt)

### Cross-build Toolchain
```
# Zig:
zig build -Dtarget=riscv64-linux-musl

# Kernel:
make ARCH=riscv CROSS_COMPILE=riscv64-linux-musl- defconfig

# Rust:
rustup target add riscv64gc-unknown-linux-musl
```

### Alpenglow Porting
- [x] Kernel: riscv64 defconfig + SBI + virt
- [x] Zig components: init, kernelctl, glowfsctl for riscv64-linux-musl
- [ ] Toybox: CROSS_COMPILE=riscv64-linux-musl-
- [ ] Dinit: CXX=riscv64-linux-musl-g++
- [x] Boot: OpenSBI + U-Boot script for riscv64
- [x] Testing: QEMU virt with OpenSBI (verified boot to Zig init)

### Quick Start (riscv64)
```sh
# Cross-compile Zig components + build initramfs + boot in QEMU
scripts/build-riscv64.sh

# Boot test
scripts/qemu-boot-riscv64.sh
```

### Boards
- SiFive HiFive Unmatched (FU740)
- StarFive VisionFive 2 (JH7110)
- QEMU virt (for testing)

## Rockchip RK3566 / PINE64 Quartz64

### Alpenglow Porting
- [x] Kernel: aarch64 defconfig with Rockchip RK3566 support
- [x] Boot: U-Boot boot script (boot.cmd)
- [x] U-Boot build: rk3566_quartz64_defconfig build script
- [ ] Hardware: flash and boot on Quartz64 Model A (real hardware)

### Build U-Boot
```sh
scripts/build-uboot-rk3566.sh
```

### Flash to SD
```sh
scripts/flash-rk3566.sh /dev/sdX
```

### Required DTBs
- `rk3566-quartz64-a.dtb` (PINE64 Quartz64 Model A)
- `rk3566-soquartz.dtb` (PINE64 SOQuartz)
- `rk3566-roc-pc.dtb` (Firefly ROC-RK3566-PC)

## Chimera Linux Reference

Chimera supports: x86_64, aarch64, riscv64, ppc64el, ppc64, ppc

All use musl + LLVM/clang as primary toolchain. Dinit is the init system.
Chimera's package manager is `apk` (Alpine's, not our custom Oil).

Key difference from Alpenglow: Chimera is a general-purpose distro,
Alpenglow is a diskless appliance. We can reuse their kernel configs
and package recipes but the rootfs design is different.

## Cross-compilation Strategy

1. **Zig** — primary cross-build tool for initramfs helpers (kernelctl, glowfsctl, init)
   - `-Dtarget=aarch64-linux-musl` or `-Dtarget=riscv64-linux-musl`
   - Produces static binaries, no sysroot needed
   
2. **Rust** — for Oil, netd, kernel modules
   - `--target aarch64-unknown-linux-musl` or `riscv64gc-unknown-linux-musl`
   - Requires musl cross-toolchain for linking
   
3. **C/C++** — for toybox, dinit
   - CROSS_COMPILE + musl-cross-make (or Zig cc as cross-compiler)

4. **Kernel** — CROSS_COMPILE + ARCH
   - `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-musl-`
   - `make ARCH=riscv CROSS_COMPILE=riscv64-linux-musl-`

See `scripts/cross-build.sh` for an automated cross-compilation pipeline.

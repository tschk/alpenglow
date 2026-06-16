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
- [ ] Kernel: aarch64 defconfig + rockchip + rust
- [ ] Initramfs: aarch64 static binaries (Zig cross-compiles)
- [ ] Toybox: CROSS_COMPILE=aarch64-linux-musl-
- [ ] Dinit: CXX=aarch64-linux-musl-g++
- [ ] Boot: U-Boot script or Limine aarch64
- [ ] Devices: UART, SD/eMMC, Ethernet, USB
- [ ] Testing: QEMU system emulation of virt+rockchip boards

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

### Boards
- SiFive HiFive Unmatched (FU740)
- StarFive VisionFive 2 (JH7110)
- QEMU virt (for testing)

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

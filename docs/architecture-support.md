# Architecture Support

General-purpose musl+LLVM Linux distribution supporting two deployment modes:
- **Diskless/Appliance** — initramfs-only, RAM root, GlowFS overlay
- **Rootfs/Desktop** — normal root-on-disk, package-managed

Both modes share the same kernel, toolchain, init system, and package manager.
The only difference is the boot flow: initramfs with switch_root vs persistent root.

## Current (x86_64)

- **Boot:** Limine (UEFI) + SeaBIOS (QEMU), or direct initramfs
- **Kernel:** Linux 7.0, CONFIG_RUST=y, defconfig+kvm_guest+rust (13MB)
- **Init:** dinit (Zig 4.8KB fallback)
- **Userland:** toybox musl static
- **Toolchain:** LLVM/Clang, Zig 0.16, Rust 1.93
- **Mode:** Diskless by default, rootfs supported
- **Branch:** `main`

## Target: aarch64

| SoC/Board | Branch | Status |
|-----------|--------|--------|
| QEMU virt (dev) | `arch/aarch64` | Config ready, kernel builds |
| RK3566 (Quartz64, SOQuartz, Radxa E25) | `board/rk3566` | Config + U-Boot script |
| RK3588 (future) | TBD | Not started |

### Kernel config
```
CONFIG_ARCH_ARM64=y
CONFIG_ARM64_VA_BITS_48=y
CONFIG_RUST=y
CONFIG_SERIAL_AMBA_PL011=y
CONFIG_VIRTIO_MMIO=y
```
Full config: `system/alpine/kernel/config-aarch64`

### Boot
- **QEMU virt:** `qemu-system-aarch64 -machine virt -cpu cortex-a57`
- **RK3566:** U-Boot (TPL/SPL) → extlinux on SD/eMMC → Linux

### Cross-build
```sh
# Kernel
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-musl- defconfig

# Zig (kernelctl, glowfsctl, init)
zig build -Dtarget=aarch64-linux-musl

# Rust (Oil, netd, kernel modules)
cargo build --target aarch64-unknown-linux-musl
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

| Board | Branch | Status |
|-------|--------|--------|
| QEMU virt (dev) | `arch/riscv64` | Config ready, kernel builds |
| StarFive VisionFive 2 | TBD | Not started |
| SiFive HiFive Unmatched | TBD | Not started |

### Kernel config
```
CONFIG_ARCH_RV64I=y
CONFIG_RISCV_SBI=y
CONFIG_SBI_CONSOLE=y
CONFIG_SERIAL_8250=y
CONFIG_RUST=y
```
Full config: `system/alpine/kernel/config-riscv64`

### Boot
- **QEMU virt:** OpenSBI + QEMU virt machine
- **Hardware:** OpenSBI + U-Boot + board-specific DTB

### Cross-build
```sh
# Kernel
make ARCH=riscv CROSS_COMPILE=riscv64-linux-musl- defconfig

# Zig
zig build -Dtarget=riscv64-linux-musl

# Rust
cargo build --target riscv64gc-unknown-linux-musl
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

| Component | Tool | Target Flag |
|-----------|------|-------------|
| kernelctl, glowfsctl, init | Zig | `-Dtarget=aarch64-linux-musl` or `riscv64-linux-musl` |
| Oil, netd, kernel modules | Rust | `--target aarch64-unknown-linux-musl` or `riscv64gc-unknown-linux-musl` |
| toybox, dinit | C/C++ | `CROSS_COMPILE=aarch64-linux-musl-` or `riscv64-linux-musl-` |
| Linux kernel | make | `ARCH=arm64 CROSS_COMPILE=aarch64-linux-musl-` or `ARCH=riscv CROSS_COMPILE=riscv64-linux-musl-` |

See `scripts/cross-build.sh` for the automated pipeline.  
U-Boot: `scripts/build-uboot-rk3566.sh` (rk3566_quartz64_defconfig)  
Flash: `scripts/flash-rk3566.sh`  
Test: `scripts/test-rk3566.md`

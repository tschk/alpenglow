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

## Cross-compilation Strategy

| Component | Tool | Target Flag |
|-----------|------|-------------|
| kernelctl, glowfsctl, init | Zig | `-Dtarget=aarch64-linux-musl` or `riscv64-linux-musl` |
| Oil, netd, kernel modules | Rust | `--target aarch64-unknown-linux-musl` or `riscv64gc-unknown-linux-musl` |
| toybox, dinit | C/C++ | `CROSS_COMPILE=aarch64-linux-musl-` or `riscv64-linux-musl-` |
| Linux kernel | make | `ARCH=arm64 CROSS_COMPILE=aarch64-linux-musl-` or `ARCH=riscv CROSS_COMPILE=riscv64-linux-musl-` |

See `scripts/cross-build.sh` for the automated pipeline.

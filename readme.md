# Alpenglow

General-purpose musl+LLVM Linux distribution. dinit init, Oil packages.
**Boots to login in &lt;1s** on native virt (x86_64 KVM or aarch64 HVF).

Two deployment modes:
- **Diskless/immutable** — initramfs-only, RAM root, GlowFS overlay (appliance mode)
- **Rootfs** — normal root-on-disk (ext4/btrfs/zfs), package-managed

```sh
scripts/boot-native.sh           # build + boot initramfs (QEMU)
system/backends/appliance/scripts/qemu.sh   # boot existing build
```

Platform support:
- x86_64 — `main` branch (primary target)
- aarch64 — `arch/aarch64` branch — QEMU virt, Apple Silicon HVF
- riscv64 — `arch/riscv64` branch — QEMU virt, OpenSBI
- Rockchip RK3566 — `board/rk3566` branch — PINE64 Quartz64

## Quick Start

```sh
# Initramfs (diskless) mode — build + boot in QEMU
./scripts/boot-native.sh

# Rootfs mode — install to disk
# I'll clean up these instructions later, and am gonna make a website or sm for this.

# Custom kernel
KERNEL_BUILD=1 ./scripts/boot-native.sh
```

## Design

| Layer | Choice | Notes |
|-------|--------|-------|
| Init | dinit | Parallel dependency graph, both modes |
| Userland | toybox (838KB), oksh | Static musl, no glibc |
| Package mgr | Oil | APK-compatible, standalone binary |
| Kernel | Linux 7.0 + Rust modules | CONFIG_RUST=y, alpenglow_core.ko |
| Kernel ctrl | kernelctl (Zig, 89KB) | Static, µs-scale startup |
| Network | netd (Rust), udhcpc, iwd | Zero-external-deps netd |
| Root FS | **Diskless:** GlowFS/erofs/squashfs in RAM. **Rootfs:** ext4 over LUKS |
| Compositor | Wayland + cage + foot | Optional, not in base |
| Security | AppArmor, read-only root (optional) | Hardened by default |
| Audio | ALSA + PipeWire |
| Kernel | Linux 7.0+ with CONFIG_RUST=y, GlowFS in-tree |

## Project Layout

```
system/
  backends/
    appliance/          Primary profile (kernel configs, dinit services, scripts)
  kernelctl-zig/        Cgroup + kernel policy (Zig, 89KB static)
  netd/                 Network state daemon (Rust, zero deps)
  glowfsctl-zig/        GlowFS image tooling (Zig, 164KB)
  oil/                  Package manager (Rust, APK-compatible)
  glowfs/               GlowFS kernel module source (C+Rust)
  kernel-modules/       Rust kernel modules (alpenglow_core, alpenglow_bootstat)
  init/                 Zig init (4.8KB static, initramfs fallback)
scripts/                Build, CI, benchmark scripts
docs/                   Architecture, build, install docs
```

Kernel configs live at `system/backends/appliance/kernel/`.

## Performance

### Boot to login (QEMU KVM, quiet)

| OS | Boot | Initramfs | Kernel | Idle RAM |
|----|------|-----------|--------|----------|
| **Alpenglow** min | **0.6s** | **1.4K** | **4.4MB** | **~17MB** |
| **Alpenglow** std | **1.3s** | 1.7MB | 4.4MB | ~26MB |
| Alpine Linux virt | 1.3s | 8.7MB | 6.5MB | ~58MB |
| Void Linux | 2.5s | 12MB | 7MB | ~80MB |
| Ubuntu Server | 15s | 40MB | 12MB | ~200MB |

Alpenglow minimal (Zig init, 4.8KB) boots in 0.6s on x86_64 KVM. The standard build (dinit + toybox + getty) is 1.3s. Alpine matches boot speed but has 6000x larger initramfs and 3x the RAM. Both modes use the same toolchain — the difference is just initramfs contents.

### Binary size (static musl, x86_64)

| Tool | Lang | Size | vs alternative |
|------|------|------|----------------|
| kernelctl | Zig | 89KB | 501KB (Rust) |
| glowfsctl | Zig | 164KB | 501KB (Rust) |
| init | Zig | 4.8KB | 937KB (toybox+sh) |
| dinit | C++ | 1.6MB | 20MB+ (systemd) |
| toybox | C | 838KB | 10MB+ (coreutils) |
| alpenglow_core.ko | Rust | 9.2K | kernel built-in |

## Modes

Alpenglow runs in two deployment modes sharing the same codebase:

**Diskless/Appliance** — boot from initramfs, root in RAM (tmpfs), state on persistent partition. Uses GlowFS squashfs for verified immutable root. Target: embedded, edge, kiosk, containers.

**Rootfs/Desktop** — install to disk (ext4 over LUKS), normal r/w root. dinit manages services, Oil installs packages. Target: workstation, server, development.

The `init` script auto-detects mode: if `/dev/disk/by-label/alpenglow-root` exists, it switches root; otherwise runs diskless. Both modes use the same kernel, toolchain, and package format.

## Services

| Service | Status | Appliance | Desktop | Managed by |
|---------|--------|-----------|---------|------------|
| SSH (dropbear) | ✅ | ✅ | ✅ | dinit |
| NTP (chronyd) | ✅ | ✅ | ✅ | dinit |
| DNS cache (dnsmasq) | ✅ | ✅ | ✅ | dinit |
| Logging (syslogd) | ✅ | ✅ | ✅ | dinit |
| DHCP networking | ✅ | ✅ | ✅ | dinit |
| WiFi (iwd) | ✅ | optional | ✅ | dinit |
| Wayland + sway | ✅ | optional | ✅ | dinit |
| Audio (PipeWire) | ✅ | optional | ✅ | dinit |
| Package manager (Oil) | ✅ | ✅ | ✅ | dinit |
| Kernel policy (kernelctl) | ✅ | ✅ | ✅ | dinit |
| GlowFS mount | ✅ | ✅ | optional | dinit |

## Status

It boots on real hardware! 22/22 milestones.
Booted on 2012 Mac Mini.

See [AGENTS.md](AGENTS.md) for full milestone table and [docs/](docs/) for architecture docs.

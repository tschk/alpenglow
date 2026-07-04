# Alpenglow

General-purpose musl+LLVM Linux distribution. dinit init, Oil packages.
**Boots to login in &lt;1s** on native virt (x86_64 KVM or aarch64 HVF).

Root model:
- **Immutable rootfs** — initramfs loads the complete OS into RAM from an erofs or squashfs image
- **Persistent state** — `/home`, package state, browser profiles, caches, and logs stay on disk under bcachefs-backed `/state`
- **Desktop** — a build profile layered on the immutable model, not a separate root-on-disk mode

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

# Custom kernel
KERNEL_BUILD=1 ./scripts/boot-native.sh
```

## Design

| Layer | Choice | Notes |
|-------|--------|-------|
| Init | dinit | Parallel dependency graph, both modes |
| Userland | toybox (838KB), oksh | Static musl, no glibc |
| Package mgr | Oil | APK-compatible, standalone binary |
| Kernel | Tracks kernel.org latest stable + Rust modules | CONFIG_RUST=y, alpenglow_core.ko |
| Kernel ctrl | kernelctl (Zig, 89KB) | Static, µs-scale startup |
| Network | netd (Rust), udhcpc, iwd | Zero-external-deps netd |
| Root FS | erofs/squashfs immutable image loaded into RAM. bcachefs for `/home` and mutable state |
| Desktop | Wayland + cage + alpenglowed + foot | `../alpenglowed` is the desktop environment |
| Security | AppArmor, read-only root (optional) | Hardened by default |
| Audio | ALSA + PipeWire |
| Kernel | kernel.org latest stable with CONFIG_RUST=y |

## Project Layout

```
system/
  backends/
    appliance/          Primary profile (kernel configs, dinit services, scripts)
  kernelctl-zig/        Cgroup + kernel policy (Zig, 89KB static)
  netd/                 Network state daemon (Rust, zero deps)
  oil/                  Package manager (Rust, APK-compatible)
  kernel-modules/       Rust kernel modules (alpenglow_core, alpenglow_bootstat)
  init/                 Zig init (4.8KB static, initramfs fallback)
scripts/                Build, CI, benchmark scripts
docs/                   Architecture, build, install docs
```

Kernel configs live at `system/backends/appliance/kernel/`.

## Profiles

Build profiles select the userspace image:

| Profile | Variable | Scope |
|---------|----------|-------|
| Minimal | `BUILD_PROFILE=minimal` | Headless boot, SSH, time, logs, DNS, OOM guard |
| Standard | `BUILD_PROFILE=standard` | Minimal plus compiler/tooling, network tools, filesystem tools, and system utilities |
| Desktop | `BUILD_PROFILE=desktop` | Standard plus Wayland, audio, WiFi, greetd, cage, `../alpenglowed`, foot, and browser shell pieces |

Kernel profiles select hardware and boot policy:

| Profile | Variable | Scope |
|---------|----------|-------|
| Fast | `KERNEL_PROFILE=fast` | Smallest headless diskless boot path |
| Minimal | `KERNEL_PROFILE=minimal` | Networked appliance kernel with cgroups, PSI, zram, seccomp, Landlock, and root image filesystems |
| Desktop | `KERNEL_PROFILE=desktop` | Minimal plus display, audio, USB, HID, WiFi, Bluetooth, firmware, and desktop filesystems |

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
| init | Zig | 4.8KB | 937KB (toybox+sh) |
| dinit | C++ | 1.6MB | 20MB+ (systemd) |
| toybox | C | 838KB | 10MB+ (coreutils) |
| alpenglow_core.ko | Rust | 9.2K | kernel built-in |

## Root And Desktop Model

Alpenglow has one root model:

**Immutable rootfs** — boot from initramfs, load the OS into RAM, and keep state on a persistent bcachefs partition. `/home`, browser profiles, package state, logs, and caches bind from `/state`; the system image stays immutable. Target: appliance, workstation, edge, kiosk, and desktop builds.

**Desktop** — `BUILD_PROFILE=desktop` adds the graphical stack and `../alpenglowed` desktop environment on top of the immutable rootfs model. It is separate from `standard`; it is not a normal root-on-disk mode.

## Services

| Service | Status | Appliance | Desktop | Managed by |
|---------|--------|-----------|---------|------------|
| SSH (dropbear) | ✅ | ✅ | ✅ | dinit |
| NTP (chronyd) | ✅ | ✅ | ✅ | dinit |
| DNS cache (dnsmasq) | ✅ | ✅ | ✅ | dinit |
| Logging (syslogd) | ✅ | ✅ | ✅ | dinit |
| DHCP networking | ✅ | ✅ | ✅ | dinit |
| WiFi (iwd) | ✅ | optional | ✅ | dinit |
| Wayland + cage + alpenglowed | ✅ | optional | ✅ | dinit |
| Audio (PipeWire) | ✅ | optional | ✅ | dinit |
| Package manager (Oil) | ✅ | ✅ | ✅ | dinit |
| Kernel policy (kernelctl) | ✅ | ✅ | ✅ | dinit |
| Root image mount | ✅ | ✅ | ✅ | initramfs |

## Status

It boots on real hardware! 22/22 milestones.
Booted on 2012 Mac Mini.

See [AGENTS.md](AGENTS.md) for full milestone table and [docs/](docs/) for architecture docs.

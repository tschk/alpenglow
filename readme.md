# Alpenglow

General-purpose musl Linux distribution. dinit init, Oil packages.
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
| Network | netd (Zig), udhcpc, iwd | Zero-external-deps netd |
| Root FS | erofs/squashfs immutable image loaded into RAM. bcachefs for `/home` and mutable state |
| Desktop | Wayland + Smithay target via alpenglowed | `../alpenglowed` is the desktop environment |
| Security | AppArmor, read-only root (optional) | Hardened by default |
| Audio | ALSA + PipeWire |
| Kernel | kernel.org latest stable with CONFIG_RUST=y |

## Project Layout

```
system/
  backends/
    appliance/          Primary profile (kernel configs, dinit services, scripts)
  kernelctl-zig/        Cgroup + kernel policy (Zig, 89KB static)
  netd-zig/             Network state daemon (Zig, zero deps)
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
| Desktop | `BUILD_PROFILE=desktop` | Standard plus Wayland, audio, WiFi, greetd, `../alpenglowed`, foot, and browser shell pieces |

Kernel profiles select hardware and boot policy:

| Profile | Variable | Scope |
|---------|----------|-------|
| Fast | `KERNEL_PROFILE=fast` | Smallest headless diskless boot path |
| Minimal | `KERNEL_PROFILE=minimal` | Networked appliance kernel with cgroups, PSI, zram, seccomp, Landlock, and root image filesystems |
| Desktop | `KERNEL_PROFILE=desktop` | Minimal plus display, audio, USB, HID, WiFi, Bluetooth, firmware, and desktop filesystems |

## Performance

### Boot target (QEMU KVM, quiet)

| OS | Boot | Initramfs | Kernel | RAM at login |
|----|------|-----------|--------|----------|
| **Alpenglow** min | **0.6s** | **1.4K** | **4.4MB** | **~17MB** |
| **Alpenglow** std | **1.3s** | 1.7MB | 4.4MB | ~26MB |
| **Alpenglow** desktop | **1.25s** | 66MB | 6.0MB | ~258MB |
| Alpine Linux virt | 1.3s | 8.7MB | 6.5MB | ~58MB |
| Void Linux | 2.5s | 12MB | 7MB | ~80MB |
| Ubuntu Server | 15s | 40MB | 12MB | ~200MB |
| Fedora minimal GNOME | 7.24s | 34MB | 18MB | ~716MB |
| Manjaro minimal XFCE | 6.82s | 24MB | 16MB | ~439MB |
| Ubuntu minimal GNOME | 35.38s | 63MB | 15MB | ~196MB |

Alpenglow minimal (Zig init, 4.8KB) boots in 0.6s on x86_64 KVM. The standard build (dinit + toybox + getty) is 1.3s. Alpine matches boot speed but has 6000x larger initramfs and 3x the RAM. Both modes use the same toolchain — the difference is just initramfs contents.

Desktop serial-login proof on `ultramarine` (`BUILD_PROFILE=desktop KERNEL_PROFILE=desktop GRAPHICAL=1 GRAPHICS_BACKEND=software QEMU_DISPLAY=none`) reached login in 1.25s with Zig-backed kernel policy, netd, zram, and pressure services enabled. The measured image had a 223MB rootfs, 66MB zstd initramfs, 6.0MB kernel, and ~258MB RAM used. This is down from the pre-trim desktop build at 689MB rootfs and 211MB initramfs. Xwayland, cage, wlroots, and the duplicate musl Mesa/LLVM stack are absent from the rootfs. This is not yet a graphical-session idle benchmark.

Fedora, Manjaro, and Ubuntu desktop rows are installed package-manager roots, not live ISOs or netinstall timings. They were built on `ultramarine` as minimal desktop images, copied to ext4 disks, and booted with the same QEMU shape used for Alpenglow comparison (`q35`, KVM, 4096MB RAM, 2 vCPU, virtio GPU, serial console). Boot time stops at systemd `graphical.target`; RAM is the last serial `/proc/meminfo` sample before that target. Fedora used GNOME/GDM from `fedora:43` packages with a 2.2GB root and 2.4GB sparse image. Manjaro used XFCE/LightDM from `manjarolinux/base:latest` packages with a 2.0GB root and 2.2GB sparse image. Ubuntu used GNOME/GDM from `ubuntu:24.04` packages with a 2.0GB root and 2.1GB sparse image.

| Desktop graphics payload | Size | Includes |
|--------------------------|------|----------|
| `GRAPHICS_BACKEND=software` | 175MB | lavapipe, LLVM, Z3 |
| `GRAPHICS_BACKEND=hardware` | 69MB | Intel, virtio, nouveau, gfxstream ICDs; no lavapipe/LLVM/Z3 |

Desktop runtime does not ship the system LLVM/Clang compiler toolchain; use the standard profile for that. `COMPILER=inauguration` selects the `../inauguration` compiler track for compiler-capable images, but it does not remove lavapipe's Mesa LLVM dependency from the graphical runtime.

### Binary size (static musl, x86_64)

| Tool | Lang | Size | vs alternative |
|------|------|------|----------------|
| kernelctl | Zig | 72KB | 501KB (Rust) |
| netd | Zig | 40KB | Rust version still in tree |
| zramctl | Zig | 16KB | shell wrapper replaced |
| pressurectl | Zig | 48KB | shell wrapper replaced |
| init | Zig | 4.8KB | 937KB (toybox+sh) |
| dinit | C++ | 1.6MB | 20MB+ (systemd) |
| toybox | C | 838KB | 10MB+ (coreutils) |
| alpenglow_core.ko | Rust | 9.2K | kernel built-in |

## Root And Desktop Model

Alpenglow has one root model:

**Immutable rootfs** — boot from initramfs, load the OS into RAM, and keep state on a persistent bcachefs partition. `/home`, browser profiles, package state, logs, and caches bind from `/state`; the system image stays immutable. Target: appliance, workstation, edge, kiosk, and desktop builds.

**Desktop** — `BUILD_PROFILE=desktop` adds the graphical stack and `../alpenglowed` desktop environment on top of the immutable rootfs model. It is separate from `standard`; it is not a normal root-on-disk mode. The compositor model is Wayland + Smithay in alpenglowed.

## Services

| Service | Status | Appliance | Desktop | Managed by |
|---------|--------|-----------|---------|------------|
| SSH (dropbear) | ✅ | ✅ | ✅ | dinit |
| NTP (chronyd) | ✅ | ✅ | ✅ | dinit |
| DNS cache (dnsmasq) | ✅ | ✅ | ✅ | dinit |
| Logging (syslogd) | ✅ | ✅ | ✅ | dinit |
| DHCP networking | ✅ | ✅ | ✅ | dinit |
| WiFi (iwd) | ✅ | optional | ✅ | dinit |
| Wayland + alpenglowed | ✅ | optional | ✅ | dinit |
| Audio (PipeWire) | ✅ | optional | ✅ | dinit |
| Package manager (Oil) | ✅ | ✅ | ✅ | dinit |
| Kernel policy (kernelctl) | ✅ | ✅ | ✅ | dinit |
| Root image mount | ✅ | ✅ | ✅ | initramfs |

## Status

QEMU boot is verified. Real hardware boot is still pending.

See [AGENTS.md](AGENTS.md) for full milestone table and [docs/](docs/) for architecture docs.

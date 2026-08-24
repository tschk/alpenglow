# Alpenglow

> [!WARNING]
> Desktop images and graphical features are unstable, testing-only, and still under active development.

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
- aarch64 — `arch/aarch64` branch — generic UEFI disk and installer ISO for UTM, ARM servers, and UEFI-capable boards
- riscv64 — `arch/riscv64` branch — QEMU virt, OpenSBI
- Rockchip RK3566 — `board/rk3566` branch — PINE64 Quartz64

## Downloads

GitHub releases publish testing-only, unstable images under active development: live installer ISOs and compressed disk images for each edition and architecture.

| Asset | Use |
|-------|-----|
| `.iso` | Live installer. Boot it to try Alpenglow, then install from the TUI or desktop installer. |
| `.img.zst` | Compressed disk image for direct flashing or scripted installs. |
| `-wsl.tar` | WSL import rootfs for `wsl --import`. |

Release asset names use:

```sh
alpenglow-VERSION-EDITION-ARCH.iso
alpenglow-VERSION-EDITION-ARCH.img.zst
alpenglow-VERSION-standard-x86_64-wsl.tar
```

WSL import:

```powershell
wsl --import Alpenglow C:\WSL\Alpenglow alpenglow-VERSION-standard-x86_64-wsl.tar
wsl -d Alpenglow
```

Standard live ISOs use the terminal installer:

```sh
alpenglow-install --tui /run/alpenglow/alpenglow.img.zst /dev/sdX
```

Desktop live ISOs boot Alpenglowed and open the graphical installer against the same bundled image at `/run/alpenglow/alpenglow.img.zst`.

Aarch64 desktop assets use a GPT disk with a FAT32 EFI System Partition and a bcachefs state partition. They boot on generic ARM64 UEFI firmware, including UTM. Non-UEFI boards need their own firmware, device tree, and boot chain before using the same disk image.

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
| Userland | toybox (838KB), oksh | Static musl. Desktop Alpenglowed currently uses an isolated glibc graphics path |
| Package mgr | Oil | APK-compatible, standalone binary |
| Kernel | Tracks kernel.org latest stable + Rust modules | CONFIG_RUST=y, alpenglow_core.ko |
| Kernel ctrl | kernelctl (Zig, 89KB) | Static, µs-scale startup |
| Network | netd (Zig), udhcpc, iwd | Zero-external-deps netd |
| Root FS | erofs/squashfs immutable image loaded into RAM. bcachefs for `/home` and mutable state |
| Desktop | Wayland + Smithay target via [Alpenglowed](https://github.com/tschk/alpenglowed) | Default graphical session. [Soliloquy](https://github.com/tschk/soliloquy) `sold` is an optional session for the internet role |
| Security | AppArmor, read-only root (optional) | Hardened by default |
| Audio | ALSA + PipeWire |
| Kernel | kernel.org latest stable with CONFIG_RUST=y |

## Project Layout

```
system/
  backends/
    appliance/          Primary profile (kernel configs, dinit services, scripts)
  alpenglow-ctl/        Multicall kernel/net/pressure/zram daemons (Zig)
  kernelctl-zig/        Deprecated build shim → alpenglow-ctl
  netd-zig/             Deprecated build shim → alpenglow-ctl
  oil/                  Package manager (Rust, APK-compatible)
  kernel-modules/       Rust kernel modules (alpenglow_core, alpenglow_bootstat)
  init/                 Zig init (4.8KB static, initramfs fallback)
scripts/                Build, CI, benchmark scripts
docs/                   Architecture, build, install docs
```

Kernel configs live at `system/backends/appliance/kernel/`.

## Editions And Roles

Alpenglow is one OS. There are three public product SKUs. Roles are session + policy + artifact on top of a SKU. `SESSION` is `none|alpenglowed|sold|cage`. `GRAPHICAL=1` in `boot-native.sh` means the Alpenglowed/glibc graphics path, not every GUI.

| SKU | Userspace | Kernel | Session | Artifact | Scope |
|-----|-----------|--------|---------|----------|-------|
| potato | `minimal` | `fast` | alpenglowed | image | Lightweight / embedded / old hardware. `alpenglowed-lite` on Cage, no PipeWire. Container export is `ALPENGLOW_ARTIFACT=oci` or `tar` |
| desktop | `desktop` | `desktop` | alpenglowed | image | Normal GUI with [Alpenglowed](https://github.com/tschk/alpenglowed), audio, WiFi, greeter. Fleet is `ALPENGLOW_FLEET=1` |
| internet | `minimal` | `minimal` | sold | image | [Soliloquy](https://github.com/tschk/soliloquy) `sold` session. Kiosk is `ALPENGLOW_KIOSK=1` or `SESSION=cage` |

```sh
ALPENGLOW_EDITION=potato
ALPENGLOW_EDITION=desktop ALPENGLOW_FLEET=1
ALPENGLOW_EDITION=internet ALPENGLOW_KIOSK=1
sh scripts/edition-resolve.sh --list
sh scripts/export-container.sh       # potato userspace tarball + OCI layout
```

Release GHA publishes `potato`, `desktop`, and `internet` for x86_64 and aarch64. Internal aliases (`fast`, `minimal`, `standard`, …) still resolve for CI. Details: [docs/editions-and-roles.md](docs/editions-and-roles.md).

Asset names: `alpenglow-v0.1.COUNT-{potato|desktop|internet}-ARCH.{iso,img.zst}` and `alpenglow-v0.1.COUNT-potato-ARCH.tar`.

## Performance

### Oil and apk (aarch64 QEMU TCG)

| Metric | Oil | apk |
|---|---:|---:|
| Cold index refresh median | 1.845 s | 2.057 s |
| Cached `search busybox` median | 0.641 s | 1.458 s |
| Binary size | 2.15 MiB | 67.6 KiB |
| Index cache | 1.78 MiB | 2.46 MiB |

Three cold runs before the cache-format change on an Alpine 3.21 aarch64 guest under QEMU TCG (not hardware or HVF). Oil's gzip cache is 5.5x smaller than its prior 9.90 MiB raw cache. Package installation was excluded because `hello` was unavailable to both commands in this guest.

### Boot target (QEMU KVM, quiet)

| OS | Boot | Initramfs | Kernel | RAM at target |
|----|------|-----------|--------|----------|
| **Alpenglow** min | **0.6s** | **1.4K** | **4.4MB** | **~17MB** |
| **Alpenglow** std | **1.15s** | 22MB | 6.0MB | ~87MB |
| **Alpenglowed Desktop with Alpenglowed** | **1.98s** | 66MB | 6.0MB | ~253MB |
| Alpine Linux virt | 1.3s | 8.7MB | 6.5MB | ~58MB |
| Void Linux | 2.5s | 12MB | 7MB | ~80MB |
| Ubuntu Server | 15s | 40MB | 12MB | ~200MB |
| Fedora minimal GNOME | 7.44s | 34MB | 18MB | ~705MB |
| Manjaro minimal XFCE | 7.44s | 24MB | 16MB | ~477MB |
| Ubuntu minimal GNOME | 35.32s | 63MB | 15MB | ~198MB |

Alpenglow minimal (Zig init, 4.8KB) boots in 0.6s on x86_64 KVM. The standard build (dinit + toybox + getty) is 1.15s as a five-run median. Alpine matches boot speed but has a larger initramfs and uses more RAM. Both modes use the same toolchain — the difference is just initramfs contents.

Alpenglow standard and Alpenglowed Desktop rows are five-run medians on `ultramarine` with KVM, 4096MB RAM, 2 vCPU, and explicit initramfs boot. Alpenglowed Desktop (`BUILD_PROFILE=desktop KERNEL_PROFILE=desktop GRAPHICAL=1 GRAPHICS_BACKEND=software QEMU_DISPLAY=none`) reached serial login with Zig-backed kernel policy, netd, zram, and pressure services enabled. The measured desktop image had a 223MB rootfs, 66MB zstd initramfs, and 6.0MB kernel. This is down from the pre-trim desktop build at 689MB rootfs and 211MB initramfs. Xwayland, cage, wlroots, and the duplicate musl Mesa/LLVM stack are absent from the rootfs. This is not yet a graphical-session idle benchmark.

Fedora, Manjaro, and Ubuntu desktop rows are five-run medians from installed package-manager roots, not live ISOs or netinstall timings. They were built on `ultramarine` as minimal desktop images, copied to ext4 disks, and booted with the same QEMU shape used for Alpenglow comparison (`q35`, KVM, 4096MB RAM, 2 vCPU, virtio GPU, serial console). Boot time stops at systemd `graphical.target`; RAM is the last serial `/proc/meminfo` sample before that target. Fedora used GNOME/GDM from `fedora:43` packages with a 2.2GB root and 2.4GB sparse image. Manjaro used XFCE/LightDM from `manjarolinux/base:latest` packages with a 2.0GB root and 2.2GB sparse image. Ubuntu used GNOME/GDM from `ubuntu:24.04` packages with a 2.0GB root and 2.2GB sparse image.

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

**Immutable rootfs** — boot from initramfs, load the OS into RAM, and keep state on a persistent bcachefs partition. `/home`, browser profiles, package state, logs, and caches bind from `/state`; the system image stays immutable. Target: potato, desktop, and internet builds.

**Desktop** — `BUILD_PROFILE=desktop` adds the graphical stack and [Alpenglowed](https://github.com/tschk/alpenglowed) desktop environment on top of the immutable rootfs model. It is separate from `standard`; it is not a normal root-on-disk mode. The compositor model is Wayland + Smithay in Alpenglowed.

## Services

| Service | Status | Appliance | Desktop | Managed by |
|---------|--------|-----------|---------|------------|
| SSH (dropbear) | ✅ | ✅ | ✅ | dinit |
| NTP (chronyd) | ✅ | ✅ | ✅ | dinit |
| DNS cache (dnsmasq) | ✅ | ✅ | ✅ | dinit |
| Logging (syslogd) | ✅ | ✅ | ✅ | dinit |
| DHCP networking | ✅ | ✅ | ✅ | dinit |
| WiFi (iwd) | ✅ | optional | ✅ | dinit |
| Wayland + Alpenglowed | ✅ | optional | ✅ | dinit |
| Audio (PipeWire) | ✅ | optional | ✅ | dinit |
| Package manager (Oil) | ✅ | ✅ | ✅ | dinit |
| Kernel policy (kernelctl) | ✅ | ✅ | ✅ | dinit |
| Root image mount | ✅ | ✅ | ✅ | initramfs |

## Status

QEMU boot is verified. Real hardware boot has also been tested on Orange Pi 3B and Mac mini 2012.

Release **v0.1.492+** consolidates kernelctl/netd/pressurectl/zramctl into `alpenglow-ctl`, drops the `alpenglow-install-tui` wrapper (`alpenglow-install --tui`), and adds GHA disk cleanup for aarch64 desktop releases.

See [AGENTS.md](AGENTS.md) for full milestone table and [docs/](docs/) for architecture docs.

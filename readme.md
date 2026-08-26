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

## Editions

Public SKUs: `potato` (small OS: old `fast` + `minimal`), `desktop`, `internet`. Default is `potato`. `fast` and `minimal` are aliases for `potato`. `standard` is `potato` plus toolchain. Matrix, aliases, and asset names: [docs/editions-and-roles.md](docs/editions-and-roles.md).

## Performance

Public SKUs measured 2026-08-26 on a Cloud Agent (Linux 6.12.94+ x86_64, QEMU 8.2.2 **TCG**; nested KVM serial was empty and discarded). Full table: [docs/editions-and-roles.md](docs/editions-and-roles.md).

| SKU | Boot to login | Kernel | Initramfs |
|-----|---------------|--------|-----------|
| `potato` | **1017 ms** (`scripts/bench-boot.sh` `ACCEL=tcg MACHINE=pc`; q35 1018 ms) | 8610816 B | 3718491 B |
| FAST slim (same guest, not a fourth SKU) | **1017 ms** median (`1016 / 1017 / 1017` pc embedded; q35 `1118 / 1017 / 1017`; `MEMORY_MB=512` `1018 / 1017 / 1016`) | 7222272 B | 2313448 B |
| `desktop` | not booted (needs Docker for alpenglowed) | not built | not built |
| `internet` | not booted (minimal kernel not rebuilt) | — | 3716444 B compose, no `sold` |

FAST slim is the potato/`FAST=1` compose with Zig `/init` (4912 B) and unused copies omitted. The 1017 ms potato boot already used that Zig `/init` (then dinit getty). Nested KVM serial was 0 bytes. RAM at login was not sampled. Historical 0.6s / 1.15s rows below are ultramarine **KVM** `FAST=1` / `BUILD_PROFILE` boots from 2026-07, not these SKU numbers.

### Oil and apk (aarch64 QEMU TCG)

| Metric | Oil | apk |
|---|---:|---:|
| Cold index refresh median | 1.845 s | 2.057 s |
| Cached `search busybox` median | 0.641 s | 1.458 s |
| Binary size | 2.15 MiB | 67.6 KiB |
| Index cache | 1.78 MiB | 2.46 MiB |

Three cold runs before the cache-format change on an Alpine 3.21 aarch64 guest under QEMU TCG (not hardware or HVF). Oil's gzip cache is 5.5x smaller than its prior 9.90 MiB raw cache. Package installation was excluded because `hello` was unavailable to both commands in this guest. Not re-run on 2026-08-25.

### Historical boot (ultramarine QEMU KVM, 2026-07 — not public SKU names)

These rows are old `BUILD_PROFILE` / `FAST=1` image boots on ultramarine (KVM, x86_64). They are **not** potato / desktop / internet SKU boots from 2026-08-25. Kept as history only.

| Image (historical name) | Boot | Initramfs | Kernel | RAM at target |
|----|------|-----------|--------|----------|
| Alpenglow `FAST=1` (Zig init) | 0.6s | 1.4K | 4.4MB | ~17MB |
| Alpenglow `BUILD_PROFILE=standard` | 1.15s | 22MB | 6.0MB | ~87MB |
| Alpenglow `BUILD_PROFILE=desktop` + Alpenglowed | 1.98s | 66MB | 6.0MB | ~253MB |
| Alpine Linux virt | 1.3s | 8.7MB | 6.5MB | ~58MB |
| Void Linux | 2.5s | 12MB | 7MB | ~80MB |
| Ubuntu Server | 15s | 40MB | 12MB | ~200MB |
| Fedora GNOME (installed root) | 7.44s | 34MB | 18MB | ~705MB |
| Manjaro XFCE (installed root) | 7.44s | 24MB | 16MB | ~477MB |
| Ubuntu GNOME (installed root) | 35.32s | 63MB | 15MB | ~198MB |

Alpenglow historical rows were five-run medians on ultramarine with KVM, 4096MB RAM, 2 vCPU. Desktop used `BUILD_PROFILE=desktop KERNEL_PROFILE=desktop GRAPHICAL=1 GRAPHICS_BACKEND=software QEMU_DISPLAY=none` (223MB rootfs, 66MB zstd initramfs, 6.0MB kernel). Fedora / Manjaro / Ubuntu desktop rows were installed package-manager roots, not live ISOs.

| Desktop graphics payload (historical) | Size | Includes |
|--------------------------|------|----------|
| `GRAPHICS_BACKEND=software` | 175MB | lavapipe, LLVM, Z3 |
| `GRAPHICS_BACKEND=hardware` | 69MB | Intel, virtio, nouveau, gfxstream ICDs; no lavapipe/LLVM/Z3 |

Desktop runtime does not ship the system LLVM/Clang compiler toolchain; use `BUILD_PROFILE=standard` (the `standard` alias) for that. `COMPILER=inauguration` selects the `../inauguration` compiler track for compiler-capable images, but it does not remove lavapipe's Mesa LLVM dependency from the graphical runtime.

### Binary size (static musl)

| Tool | Lang | Size | Notes |
|------|------|------|----------------|
| alpenglow-ctl (multicall) | Zig | 163032 B | measured 2026-08-25, Zig 0.16.0 `-Drelease=true` x86_64-linux-musl (kernelctl/netd/zram/pressure are one binary) |
| alpenglow-kernelctl | Zig | 161408 B | measured 2026-08-25, aarch64-linux-musl |
| init | Zig | 4912 B | measured 2026-08-25, `-O ReleaseSmall` x86_64 and aarch64 |
| dinit | C++ | 1.6MB | not re-measured 2026-08-25 |
| toybox | C | 838KB | not re-measured 2026-08-25 |
| alpenglow_core.ko | Rust | 9.2K | not re-measured 2026-08-25 |

## Root And Desktop Model

Alpenglow has one root model:

**Immutable rootfs** — boot from initramfs, load the OS into RAM, and keep state on a persistent bcachefs partition. `/home`, browser profiles, package state, logs, and caches bind from `/state`; the system image stays immutable. Target: potato, desktop, and internet builds.

**Desktop** — `BUILD_PROFILE=desktop` adds the graphical stack and [Alpenglowed](https://github.com/tschk/alpenglowed) desktop environment on top of the immutable rootfs model. It is separate from `standard`; it is not a normal root-on-disk mode. Alpenglowed is a Wayland client on Cage. Smithay `--compositor` is experimental and is not built into the image.

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

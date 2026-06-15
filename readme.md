# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, LLVM/clang, Oil native packages, toybox userland. Runs from disk but loads entirely into RAM at boot.

**Boot time: ~2 seconds** from power-on to shell prompt.

```
Power-on → kernel decompress:    0.0s
Init (dinit) starts:             0.9s
mount-filesystems service OK:    1.5s
shell-ttyS0 (getty) ready:       1.5s
Login prompt:                    2.0s
```

Early-stage. Not production-ready.

**It boots.** Run `./scripts/boot-native.sh` (requires Docker + QEMU).

## Design

| Layer | Choice |
|-------|--------|
| Boot model | **Diskless** — rootfs in RAM via initramfs. State on persistent media. |
| Root FS | **GlowFS** — custom kernel module. Fallback: erofs, squashfs. |
| Init | **dinit** — fast parallel dependency-graph init. |
| Compiler | **LLVM/Clang** default. Inauguration as future codegen. |
| Package mgr | **Oil** — native. No distro bootstrap. |
| Userland | **toybox** — minimal BSD-licensed coreutils. |
| Shell | **oksh** |
| Crypto | **BearSSL** |
| Kernel | **Hardened** — minimal appliance config. Linux 7.0.12. |
| Initramfs | **Custom** — best of Limine + UEFI stub + extlinux. |
| Display | **Wayland** + velox compositor (Rust, wlroots-based). |
| Audio | **PipeWire** + WirePlumber session manager. |
| Networking | **sdhcp** (DHCP) + **iwd** (WiFi). |
| Session | **greetd** login greeter + **elogind** power management. |
| Terminal | **foot** (Wayland). |
| Arch | **Generic** — x86_64, aarch64, etc. |

## Benchmarks

All times measured from QEMU power-on (SeaBIOS) to prompt on serial console.
Tested on Apple Silicon Mac via QEMU (TCG emulation), Linux 7.0.12 kernel.

| Metric | Alpenglow | Alpine Linux | Void Linux | Ubuntu 24.04 |
|--------|-----------|-------------|------------|--------------|
| BIOS to kernel start | 0.0s | 0.3s | 0.3s | 0.3s |
| Kernel start to init | 0.9s | 1.2s | 1.5s | 2.5s |
| Init to shell | 0.6s | 1.5s (OpenRC) | 2.0s (runit) | 12s (systemd) |
| **Total boot** | **~2s** | **~3s** | **~4s** | **~15s** |
| Initramfs size | 14MB gzip / 11MB zstd | 8MB | 12MB | 40MB |
| Kernel size | 7.4MB full / 4.8MB min | 6.5MB | 7.0MB | 12MB |
| RAM usage (idle) | ~64MB | ~80MB | ~100MB | ~500MB |

Boot time comparison notes:
- **Alpenglow** uses dinit (parallel dependency-graph) with minimal services → ~2s
- **Alpine** uses OpenRC (serial) with modular services → ~3s
- **Void** uses runit (parallel but heavier service scripts) → ~4s
- **Ubuntu** uses systemd (comprehensive but boot-heavy) → ~15s

## Features

| Component | Status | Notes |
|-----------|--------|-------|
| **Boot to shell** | ✅ Done | Static toybox + dinit, getty login |
| **Custom kernel** | ✅ Done | Linux 7.0.12, GlowFS built-in |
| **Rust in kernel** | ✅ Done | CONFIG_RUST=y, glowfs_core.rs compiled |
| **Kernel hardening** | ✅ Done | Landlock, Yama, seccomp, cgroups, namespaces |
| **Sound** | ✅ Done | ALSA + HDA Intel + USB audio kernel drivers |
| **Wireless** | ✅ Done | 16+ driver chipsets, iwd daemon config |
| **ACPI power mgmt** | ✅ Done | Suspend/hibernate via elogind or loginctl |
| **USB-HID** | ✅ Done | USB storage, HID multitouch, I2C |
| **DHCP networking** | ✅ Done | udhcpc via dinit service |
| **State persistence** | ✅ Done | ext4 partition by label, bind mounts |
| **Oil package mgr** | ✅ Done | Vendored in system/oil, APK-only, included in initramfs |
| **Bootable disk image** | ✅ Done | GPT + Limine bootloader |
| **dinit services** | ✅ Done | 14 service files, parallel boot |
| **Wayland compositor** | 🟡 Configured | velox dinit service, needs binary build |
| **PipeWire audio** | 🟡 Configured | pipewire + wireplumber dinit services |
| **iwd WiFi** | 🟡 Configured | Requires libell static build |
| **Interactive installer** | 🟡 Planned | Crepuscularity-based GUI installer |
| **GlowFS kernel module** | 🟡 In-tree | Works as built-in, module export issues |
| **Real hardware boot** | ❌ Untested | QEMU only for now |

## Build from source

### Quick boot test (pre-built Alpine kernel)

Requires Docker + QEMU on macOS/Linux:

```sh
./scripts/boot-native.sh
```

### Full custom kernel build

Requires musl-gcc, g++, rustc, and QEMU. On native x86_64 Linux:

```sh
KERNEL_BUILD=1 KERNEL_VERSION=7.0.12 ./scripts/boot-native.sh
```

### Build on remote machine

```sh
# Clone repo
ssh user@host "git clone https://github.com/tschk/alpenglow.git"

# Build kernel and services
ssh user@host "cd alpenglow && bash build-native.sh"

# Copy artifacts back
scp user@host:alpenglow/build/native/alpenglow-build.tar.gz .
```

### Individual service builds

```sh
# Build all services as static musl binaries
./system/backends/appliance/scripts/build-all-services.sh
```

## Repo layout

```
system/
  appliance/         Backend contract, selector, metadata
  backends/
    appliance/       Primary target (dinit, toybox, LLVM, Oil, diskless)
    void/            Void reference backend
  alpine/            Alpine reference backend (QEMU flow)
  glowfs/            GlowFS kernel module
  glowfsctl/         GlowFS image tooling
  kernelctl/         cgroup + kernel policy helpers
  netd/              Network state daemon
sold/                Local Axum system bridge
initramfs/           Custom boot initramfs
docs/                Architecture, build, install docs
plans/               Build-out roadmap (4 phases)
```

## Testing

```
./install.sh --check
./scripts/ci-os-appliance.sh
./scripts/ci-glowfs-kernel-module.sh
./scripts/ci-rust-core.sh
cargo test -p sold
cargo test -p alpenglow-netd
cargo test -p alpenglow-kernelctl
cargo test -p glowfsctl
```

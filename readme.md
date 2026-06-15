# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil native packages, toybox userland. ~1.8s boot to login in QEMU.

```sh
./scripts/boot-native.sh   # needs Docker + QEMU
```

## Design

| Layer | Choice |
|-------|--------|
| Boot | Diskless (initramfs) — root in RAM, state on persistent media |
| Root FS | GlowFS / erofs — immutable kernel module |
| Init | dinit — parallel dependency-graph init |
| Userland | toybox — minimal BSD coreutils |
| Shell | oksh |
| Package mgr | **Oil** (Rust) — APK-only, 2.3K LOC, 9 deps |
| Kernel ctrl | **kernelctl** (Zig) — 89KB static binary |
| Network | netd (Rust) + udhcpc + iwd |
| Compositor | cage + foot — kiosk Wayland |
| Audio | ALSA + PipeWire — kernel drivers + dinit services |
| Kernel | Hardened Linux 7.0.12 — minimal appliance config, GlowFS built-in |

## Metrics vs Other OSes

All measurements: QEMU KVM on x86_64 (or bare metal). Alpenglow uses direct kernel boot + minimal initramfs (toybox 838KB + dinit 3.4MB). Other distros use default installer images.

### Boot to login

| OS | Time | Storage | Idle RAM | Init | Userland |
|----|------|---------|----------|------|----------|
| **Alpenglow** | **1.8s** | **34MB** (initramfs) | **~30MB** | dinit | toybox |
| Alpine Linux | 3s | 300MB | ~80MB | OpenRC | busybox |
| Void Linux | 4s | 500MB | ~100MB | runit | glibc + coreutils |
| Ubuntu Server | 15s | 2GB | ~200MB | systemd | gnu coreutils |
| Fedora Server | 14s | 3GB | ~250MB | systemd | gnu coreutils |
| Windows 11 | 20-30s | 25GB | ~3GB | ntoskrnl | — |

### Binary size (static musl, x86_64, ReleaseSmall)

| Component | Alpenglow | Typical Alternative |
|-----------|-----------|-------------------|
| kernelctl (cgroup/policy) | 89KB (Zig) | 501KB (Rust) |
| glowfsctl (image tooling) | 164KB (Zig) | 501KB (Rust) |
| init | 3.4MB (dinit) | 20MB+ (systemd) |
| userland | 838KB (toybox) | 10MB+ (coreutils) |

### RAM breakdown (Alpenglow idle, after boot)

| Component | Size |
|-----------|------|
| Kernel (code+data+page tables) | ~22MB |
| dinit + getty | ~4MB |
| toybox applets | ~1MB |
| Initramfs cpio | ~1MB |
| Slab caches / buffers | ~2MB |
| **Total** | **~30MB** |

Measured: MemTotal 480MB, MemAvailable 451MB on 512MB QEMU VM = ~30MB used.

## Repo Layout

```
system/
  kernelctl-zig/    Cgroup + kernel policy (Zig, 89KB static)
  netd/             Network state daemon (Rust)
  glowfsctl-zig/    GlowFS image tooling (Zig, 164KB static)
  oil/              Native package manager (Rust, APK-only)
  backends/
    appliance/      Primary target (dinit, toybox, LLVM)
    void/           Void reference backend
  alpine/           Alpine reference / QEMU boot flow
  glowfs/           GlowFS kernel module
initramfs/          Custom boot initramfs
docs/               Architecture, build, install docs
```

## CI

| Gate | Script |
|------|--------|
| Rust core | `scripts/ci-rust-core.sh` — cargo check + test all crates |
| Zig code | `scripts/ci-zig.sh` — zig build kernelctl-zig + glowfsctl-zig (0.16, musl) |
| OS appliance | `scripts/ci-os-appliance.sh` — policy validation |
| GlowFS module | `scripts/ci-glowfs-kernel-module.sh` — compile vs Linux headers |
| Boot benchmark | `scripts/bench-boot.sh` — QEMU boot time phases |

## Build

```sh
# Quick boot (needs Docker + QEMU) — standard profile (display, audio, WiFi, dev)
./scripts/boot-native.sh

# Minimal profile — headless server (SSH, NTP, logging, cron, DNS, no display)
BUILD_PROFILE=minimal ./scripts/boot-native.sh

# Oil-based build (uses ALPENGLOW_PROFILE=minimal|standard)
ALPENGLOW_PROFILE=minimal ./system/backends/appliance/scripts/build-rootfs.sh

# Custom kernel build
KERNEL_BUILD=1 KERNEL_VERSION=7.0.12 ./scripts/boot-native.sh

# Build individual components
cargo build --release
(cd system/kernelctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)
(cd system/glowfsctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)

# Disk image (GPT + Limine + initramfs + kernel)
./scripts/build-release.sh
```

## Status

| Feature | Status |
|---------|--------|
| Boot to shell + login | ✅ ~1.8s |
| DHCP networking | ✅ udhcpc |
| State persistence (ext4) | ✅ auto-mount by label |
| Oil package manager (APK) | ✅ in initramfs |
| kernelctl (Zig, 89KB static) | ✅ CI-built |
| Wayland display (cage+foot) | ✅ |
| Audio (ALSA+PipeWire) | ✅ dinit services |
| WiFi (iwd) | ✅ 16+ driver chipsets |
| SSH server (dropbear) | ✅ dinit-managed |
| NTP (chrony) | ✅ dinit-managed |
| Logging (syslogd) | ✅ dinit-managed |
| Cron (crond) | ✅ dinit-managed |
| DNS caching (dnsmasq) | ✅ dinit-managed |
| Editor (vro) | ✅ in-repo binary, replaces vi |
| Build profiles | ✅ minimal (headless) / standard (desktop) |
| Power management | ✅ /sys/power, no elogind |
| Interactive installer | 🟡 Planned |
| GlowFS kernel module | 🟡 In-tree, export issues |
| Real hardware boot | ❌ QEMU only |

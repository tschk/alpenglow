# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil packages. ~1.8s boot to login.

```
./scripts/boot-native.sh   # needs Docker + QEMU
```

## Design

| Layer | Choice |
|-------|--------|
| Boot | Diskless (initramfs) — root in RAM |
| Root FS | GlowFS (kernel module) |
| Init | dinit — parallel dependency graph |
| Userland | toybox (838KB), oksh |
| Package mgr | Oil (Rust, APK-only, 2.3K LOC) |
| Kernel ctrl | kernelctl (Zig, 89KB static) |
| Network | netd (Rust) + udhcpc + iwd |
| Compositor | Wayland + cage + foot |
| Audio | ALSA + PipeWire |

## Performance

All on same hardware: x86_64, QEMU KVM, 512MB RAM, 2 vCPUs, Alpine virt kernel 6.12.

### Boot to login

| Config | Initramfs | Kernel | Idle RAM (measured) | Boot time |
|--------|-----------|--------|---------------------|-----------|
| Alpenglow minimal | 1.4MB | 12MB | ~30MB | ~1.8s |
| Alpenglow standard | 1.4MB | 12MB | ~30MB | ~2.0s |
| Alpine Linux virt | 8.7MB | 12MB | 60-80MB * | ~3s |

\* Alpine estimate: doesn't print memory info to serial console.  
Alpenglow RAM: 480MB total, ~450MB available across 3 runs (kernel 22MB + dinit/getty 4MB + slab 2MB + toybox 1MB).  
Boot time: kernel decompress → services → login prompt. zstd-19 initramfs, dinit parallel startup.

### Storage

| | Initramfs (compressed) | Rootfs on disk |
|--|----------------------|----------------|
| Alpenglow | 1.4MB (min) / 34MB (full) | none (diskless) |
| Alpine virt | 8.7MB | 300MB+ |

### Binary size (static musl, x86_64)

| Tool | Alpenglow | Alternative |
|------|-----------|-------------|
| kernelctl | 89KB (Zig) | 501KB (Rust) |
| init | 3.4MB (dinit) | 20MB+ (systemd) |
| userland | 838KB (toybox) | 10MB+ (coreutils) |

## Services

| Service | Status |
|---------|--------|
| Boot to login | ✅ ~1.8s |
| DHCP networking | ✅ udhcpc |
| State persistence (ext4) | ✅ auto-mount by label |
| Oil package manager | ✅ APK install/upgrade/remove/pin |
| kernelctl (cgroups + sysctl) | ✅ 89KB Zig |
| WiFi | ✅ iwd (16+ drivers) |
| SSH server | ✅ dropbear (drops to dropbear user) |
| NTP | ✅ chrony (drops to chrony user) |
| DNS cache | ✅ dnsmasq (drops to dnsmasq user) |
| System logger | ✅ syslogd |
| Cron | ✅ crond |
| APK signature verify | ✅ CMS/RSA PKCS#1 v1.5 |
| GlowFS kernel module | 🟡 in-tree, export issues |
| Real hardware boot | ❌ QEMU only |

Desktop services (Wayland, cage, foot, pipewire, elogind) are installable via Oil but not in the base image.

## Repo Layout

```
system/
  kernelctl-zig/    Cgroup + kernel policy (Zig)
  netd/             Network state daemon (Rust)
  glowfsctl/        GlowFS image tooling (Rust)
  glowfsctl-zig/    Same in Zig (164KB)
  oil/              APK package manager (Rust)
  backends/appliance/  Primary target
  glowfs/           Kernel module source
initramfs/          Custom boot initramfs
docs/               Architecture, build, install docs
```

## CI

| Gate | Script |
|------|--------|
| Rust core | `scripts/ci-rust-core.sh` — cargo check + test |
| Zig code | `scripts/ci-zig.sh` — build kernelctl + glowfsctl (0.16, musl) |
| GlowFS module | `scripts/ci-glowfs-kernel-module.sh` |
| Multi-OS bench | `scripts/bench-all.sh` — boot time + RAM vs Alpine |
| Boot benchmark | `scripts/bench-boot.sh` |

## Build

```
# Quick boot (needs Docker + QEMU)
./scripts/boot-native.sh

# Custom kernel
KERNEL_BUILD=1 KERNEL_VERSION=7.0.12 ./scripts/boot-native.sh

# Multi-OS benchmark (Alpenglow vs Alpine, needs KVM)
./scripts/bench-all.sh

# Build components
cargo build --release
(cd system/kernelctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)
(cd system/glowfsctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)
```

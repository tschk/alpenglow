# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil packages. ~2s boot to login (KVM).

```sh
scripts/boot-native.sh   # needs Docker + QEMU
system/backends/appliance/scripts/qemu.sh   # boot existing build
```

## Quick Start

```sh
# One-shot: build + boot in QEMU
./scripts/boot-native.sh

# Boot only (if artifacts exist)
system/backends/appliance/scripts/qemu.sh

# Custom kernel + GlowFS module
KERNEL_BUILD=1 ./scripts/boot-native.sh

# Minimal profile (just shell, no display services)
BUILD_PROFILE=minimal ./scripts/boot-native.sh

# CI test (validates boot to login)
./scripts/ci-qemu-appliance.sh
```

## Design

| Layer | Choice |
|-------|--------|
| Boot | Diskless (initramfs) — root in RAM |
| Root FS | GlowFS (kernel module), fallback erofs/squashfs |
| Init | dinit — parallel dependency graph |
| Userland | toybox (838KB), oksh |
| Package mgr | Oil (Rust, APK-only, 701 LOC) |
| Kernel ctrl | kernelctl (Zig, 89KB static) |
| Network | netd (Rust, 455 LOC) + udhcpc + iwd |
| Compositor | Wayland + cage + foot |
| Audio | ALSA + PipeWire |
| Kernel | Linux 7.0+ with CONFIG_RUST=y, GlowFS in-tree |

## Project Layout

```
system/
  backends/
    appliance/          Primary backend (kernel configs, dinit, scripts)
    void/               Void reference backend (deprecated)
  alpine/               Legacy Alpine reference (kernel configs symlinked)
  kernelctl-zig/        Cgroup + kernel policy (Zig, 89KB static)
  netd/                 Network state daemon (Rust, 455 LOC)
  glowfsctl-zig/        GlowFS image tooling (Zig, 164KB)
  oil/                  Package manager (Rust, APK-only, 701 LOC)
  glowfs/               GlowFS kernel module source
scripts/                Build, CI, benchmark scripts
docs/                   Architecture, build, install docs
```

Kernel configs live at `system/backends/appliance/kernel/`.

## Performance

Measured on x86_64 with KVM. On macOS arm64 with TCG emulation expect ~60s.

### Boot to login (QEMU KVM, 512MB RAM, 2 vCPUs)

| Config | Initramfs | Kernel | Boot time |
|--------|-----------|--------|-----------|
| Alpenglow minimal | 1.4MB | 12MB | ~1.3s |
| Alpenglow standard | 2.0MB | 12MB | ~1.3s |
| Alpine Linux virt | 8.7MB | 12MB | ~1.3s |

### Binary size (static musl, x86_64)

| Tool | Size | Compared to |
|------|------|-------------|
| kernelctl | 89KB (Zig) | 501KB (Rust version) |
| dinit | 1.6MB | 20MB+ (systemd) |
| toybox | 838KB | 10MB+ (coreutils) |

## Services

| Service | Status | Managed by |
|---------|--------|------------|
| SSH (dropbear) | ✅ | dinit |
| NTP (chronyd) | ✅ | dinit |
| DNS cache (dnsmasq) | ✅ | dinit |
| Logging (syslogd) | ✅ | dinit |
| Cron (crond) | ✅ | dinit |
| DHCP networking | ✅ | dinit |
| WiFi (iwd) | ✅ | dinit |
| Wayland display | ✅ | dinit |
| Audio (PipeWire) | ✅ | dinit |
| Package manager (Oil) | ✅ | dinit |
| Kernel policy (kernelctl) | ✅ | dinit |

## Status

21/22 milestones complete. Last milestone: real hardware boot (QEMU only for now).

See [AGENTS.md](AGENTS.md) for full milestone table and [docs/](docs/) for architecture docs.

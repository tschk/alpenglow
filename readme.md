# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil packages. **Boots to login in &lt;1s** on native virt (x86_64 KVM or aarch64 HVF).

```sh
scripts/boot-native.sh                      # x86_64: build + boot (needs Docker)
scripts/build-aarch64.sh                    # aarch64: cross-compile + fetch kernel
scripts/qemu-boot-aarch64.sh                # aarch64: boot with HVF (fast on macOS)
system/backends/appliance/scripts/qemu.sh   # boot existing x86_64 build
scripts/build-aarch64.sh                     # aarch64: cross-compile + boot
scripts/qemu-boot-aarch64.sh                 # boots in ~0.6s with HVF (macOS)
```

Platform support:
- x86_64 — main branch (primary target)
- aarch64 — `arch/aarch64` branch, boots on QEMU virt and Apple Silicon (HVF)
- riscv64 — `arch/riscv64` branch, boots on QEMU with OpenSBI
- Rockchip RK3566 — `board/rk3566` branch, boots on PINE64 Quartz64

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

### Boot to login

| OS | Boot | Initramfs | Kernel | Idle RAM |
|----|------|-----------|--------|----------|
| **Alpenglow** min | **0.6s** | **1.4K** | **6MB** | **~8MB** |
| **Alpenglow** std | **1.3s** | 1.7MB | 11MB | ~12MB |
| Alpine Linux virt | 1.3s | 8.7MB | 6.5MB | ~58MB |
| Void Linux | 2.5s | 12MB | 7MB | ~80MB |
| Ubuntu Server | 15s | 40MB | 12MB | ~200MB |

Alpenglow minimal (Zig init, 4.8KB) boots in 0.6s on x86_64 KVM and aarch64 HVF. The standard build (dinit + toybox + getty) is 1.3s. Alpine matches boot speed but has 6000x larger initramfs and uses 5x the RAM.

### Binary size (static musl, x86_64)

| Tool | Size | vs alternative |
|------|------|----------------|
| kernelctl | 89KB (Zig) | 501KB (Rust) |
| dinit | 1.6MB | 20MB+ (systemd) |
| toybox | 838KB | 10MB+ (coreutils)
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

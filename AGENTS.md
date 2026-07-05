# AGENTS.md - Alpenglow Project Guide

## What is Alpenglow?

Diskless, hardened, immutable Linux appliance. erofs/squashfs RAM root, dinit init, Oil native packages, toybox userland. ~2s boot to login.

Early-stage. Not production-ready.

## Design

| Decision | Choice |
|----------|--------|
| Boot | Diskless — full OS in RAM via initramfs |
| Root FS | erofs/squashfs for immutable RAM root. bcachefs for `/state` and `/home` |
| Init | dinit — parallel dependency-graph |
| Compiler | Standard profile ships LLVM/Clang; Inauguration track selectable via COMPILER=inauguration |
| Package mgr | Oil (Rust) — APK-only, sync HTTP, 2.3K LOC |
| Userland | toybox — minimal BSD coreutils |
| Shell | oksh |
| Kernel | Hardened — three profiles: `fast` (boot speed), `minimal` (SSH/net/time/logs), `desktop` (display/audio/WiFi). Tracks kernel.org latest stable |
| Kernel ctrl | kernelctl — Zig (72KB static) + Rust (501KB static) |
| Display | Wayland + Smithay target via Alpenglowed + foot |
| Audio | ALSA + PipeWire |
| Networking | udhcpc + iwd |
| Arch | x86_64, aarch64 (aarch64 CI cross-compile only; x86_64 boot-tested in CI) |

### What's not in the base (by design)

Diskless appliance — system root lives in RAM. Persistent user and system state lives on disk under `/state`, with `/home` bind-mounted from bcachefs-backed state.
VPN, Tailscale, WireGuard, custom firewall rules — users install
via Oil or drop a binary in /usr/local. No need to bloat the base
image with something only some deployments use. Same logic applies
to any userspace service: base provides SSH + networking + package
manager, user adds what they need.

Build profile system keeps the line clear:
minimal = what you need to boot, connect SSH, and have time+logs.
standard = more than minimal: compiler/tooling, network tools, filesystem tools, and system utilities.
desktop = plug-and-play desktop: display/audio/WiFi/greetd/alpenglowed/foot.
Everything else is `oil install <pkg>` away.

Desktop runtime does not ship the system LLVM/Clang compiler toolchain; use standard for that. `COMPILER=inauguration` selects the `../inauguration` compiler track, but lavapipe's Mesa LLVM dependency is a graphics-runtime issue, not a compiler-track issue.

Kernel profiles are separate from build profiles:
fast = smallest headless diskless boot path.
minimal = networked appliance kernel with cgroups, PSI, zram, seccomp, Landlock, and root image filesystems.
desktop = minimal plus display, audio, USB, HID, WiFi, Bluetooth, firmware, and desktop filesystems.

## Architecture

```
Initramfs — Custom boot layer (Limine+UEFI+extlinux)
Immutable root image — erofs/squashfs loaded into RAM
dinit — Dependency-graph init (PID 1)
Oil — Native APK package manager (Rust)
toybox — Minimal core userland
kernelctl — Kernel policy + cgroup tooling (Zig+Rust)
alpenglow-netd — Network state daemon (Zig)
```

## Project Layout

```
system/
  kernelctl-zig/    Cgroup + kernel policy (Zig, 72KB static)
  netd-zig/         Network state daemon (Zig)
  oil/              Native package manager (Rust, APK-only)
  backends/
    appliance/      Primary target (dinit, toybox, Oil, diskless)
docs/               Architecture, build, install docs

Kernel configs live at `system/backends/appliance/kernel/`.
```

## CI

| Gate | Script | What |
|------|--------|------|
| Rust core | `scripts/ci-rust-core.sh` | cargo check + test all crates |
| Rust audit | `.github/workflows/ci.yml` | cargo audit on dependencies |
| Zig code | `scripts/ci-zig.sh` | zig build kernelctl-zig and small system helpers |
| OS appliance | `scripts/ci-os-appliance.sh` | Policy contract validation |
| Boot benchmark | `scripts/bench-boot.sh` | QEMU boot time measurement |
## Testing

```sh
./scripts/ci-rust-core.sh
./scripts/ci-zig.sh              # skip if no zig
./scripts/ci-os-appliance.sh
./scripts/bench-boot.sh          # needs built disk image
```

## Status

| Milestone | Status | Notes |
|-----------|--------|-------|
| Boot to shell + login | ✅ | ~2s, dinit + getty |
| DHCP networking | ✅ | udhcpc via dinit |
| State persistence | ✅ | bcachefs target for `/state`, bind mounts for `/home` and mutable state |
| Oil package mgr | ✅ | APK-only, in initramfs |
| Wayland display | ✅ | alpenglowed Smithay compositor + foot |
| Audio | ✅ | ALSA + PipeWire dinit services |
| WiFi | ✅ | iwd daemon, 16+ drivers |
| Power management | ✅ | /sys/power, no elogind |
| SSH server | ✅ | dropbear, dinit-managed |
| NTP (chrony) | ✅ | chronyd, dinit-managed |
| Logging (syslogd) | ✅ | toybox syslogd, dinit-managed |
| Cron (crond) | ✅ | toybox crond, dinit-managed |
| DNS caching (dnsmasq) | ✅ | dnsmasq, dinit-managed |
| Editor (vro) | ✅ | replaces toybox vi |
| Bootable disk image | ✅ | GPT + Limine |
| kernelctl Zig | ✅ | 72KB static, built in CI |
| Custom kernel build | ✅ | `KERNEL_BUILD=1` works |
| Immutable root image | ✅ | erofs/squashfs active |
| Real hardware boot | ✅ | Tested on Orange Pi 3B and Mac mini 2012 |
| Build profiles | ✅ | `BUILD_PROFILE=minimal|standard|desktop` |
| Interactive installer | 🟡 | Planned |
| Alpenglowed DE | ✅ | Alpenglowed desktop shell |

## SSH Hosts (for cross-compilation testing)

| Host | IP | User | OS | Tools |
|------|-----|------|----|-------|
| ultramarine | 192.168.4.134 | undivisible | Ultramarine (Fedora-like, glibc), WSL2, x86_64 | zig 0.14, cargo 1.93, docker, qemu+kvm |
| chimera | 192.168.4.168 | undivisible | Chimera Linux (musl), x86_64 | cargo/rustc, /dev/kvm, no zig/docker/qemu |

Alpenglow targets musl+Linux (Chimera-style). Use ultramarine for Zig builds and QEMU boot testing (has docker, qemu+kvm).

## Language Tooling Notes

- **Rust**: Oil package manager. Sync-only, no tokio. ~2.3K LOC total.
- **Zig**: kernelctl, netd, zramctl, pressurectl, and small initramfs helpers. Targets <100KB initramfs helpers.
- **Zig**: kernelctl (72KB static, 7x smaller than Rust). Targets <100KB initramfs helpers.
- **Equilibrium** (external): Zig/Nim/D/Rust FFI bridge. Not integrated yet.

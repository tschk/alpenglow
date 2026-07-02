# AGENTS.md - Alpenglow Project Guide

## What is Alpenglow?

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil native packages, toybox userland. ~2s boot to login.

Early-stage. Not production-ready.

## Design

| Decision | Choice |
|----------|--------|
| Boot | Diskless — rootfs in RAM via initramfs |
| Root FS | GlowFS (kernel module). Fallback: erofs, squashfs |
| Init | dinit — parallel dependency-graph |
| Compiler | LLVM/Clang default. Inauguration as future codegen |
| Package mgr | Oil (Rust) — APK-only, sync HTTP, 2.3K LOC |
| Userland | toybox — minimal BSD coreutils |
| Shell | oksh |
| Kernel | Hardened — minimal appliance config. Tracks kernel.org latest stable |
| Kernel ctrl | kernelctl — Zig (89KB static) + Rust (501KB static) |
| Display | Wayland + cage+foot |
| Audio | ALSA + PipeWire |
| Networking | udhcpc + iwd |
| Arch | x86_64, aarch64 (aarch64 CI cross-compile only; x86_64 boot-tested in CI) |

### What's not in the base (by design)

Diskless appliance — rootfs lives in RAM, no disk to encrypt.
VPN, Tailscale, WireGuard, custom firewall rules — users install
via Oil or drop a binary in /usr/local. No need to bloat the base
image with something only some deployments use. Same logic applies
to any userspace service: base provides SSH + networking + package
manager, user adds what they need.

Build profile system (minimal vs standard) keeps the line clear:
minimal = what you need to boot, connect SSH, and have time+logs.
standard = adds display/audio/WiFi/dev for a desktop experience.
Everything else is `oil install <pkg>` away.

## Architecture

```
Initramfs — Custom boot layer (Limine+UEFI+extlinux)
GlowFS — Kernel module for immutable root FS
dinit — Dependency-graph init (PID 1)
Oil — Native APK package manager (Rust)
toybox — Minimal core userland
kernelctl — Kernel policy + cgroup tooling (Zig+Rust)
alpenglow-netd — Network state daemon (Rust)
```

## Project Layout

```
system/
  kernelctl-zig/    Cgroup + kernel policy (Zig, 89KB static)
  netd/             Network state daemon (Rust)
  glowfsctl-zig/    GlowFS image tooling (Zig, 164KB)
  oil/              Native package manager (Rust, APK-only)
  backends/
    appliance/      Primary target (dinit, toybox, LLVM, Oil, diskless)
  glowfs/           GlowFS kernel module source
docs/               Architecture, build, install docs

Kernel configs live at `system/backends/appliance/kernel/`.
```

## CI

| Gate | Script | What |
|------|--------|------|
| Rust core | `scripts/ci-rust-core.sh` | cargo check + test all crates |
| Rust audit | `.github/workflows/ci.yml` | cargo audit on dependencies |
| Zig code | `scripts/ci-zig.sh` | zig build kernelctl-zig + glowfsctl-zig |
| OS appliance | `scripts/ci-os-appliance.sh` | Policy contract validation |
| GlowFS module | `scripts/ci-glowfs-kernel-module.sh` | Compile vs Linux headers |
| Boot benchmark | `scripts/bench-boot.sh` | QEMU boot time measurement |
## Testing

```sh
./scripts/ci-rust-core.sh
./scripts/ci-zig.sh              # skip if no zig
./scripts/ci-os-appliance.sh
./scripts/ci-glowfs-kernel-module.sh
./scripts/bench-boot.sh          # needs built disk image
cargo test -p alpenglow-netd
```

## Status

| Milestone | Status | Notes |
|-----------|--------|-------|
| Boot to shell + login | ✅ | ~2s, dinit + getty |
| DHCP networking | ✅ | udhcpc via dinit |
| State persistence | ✅ | ext4 by label, bind mounts |
| Oil package mgr | ✅ | APK-only, in initramfs |
| Wayland display | ✅ | cage + foot |
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
| kernelctl Zig | ✅ | 89KB static, built in CI |
| Custom kernel build | ✅ | `KERNEL_BUILD=1` works, GlowFS in-tree |
| GlowFS kernel module | ✅ | In-tree, weak C fallback for Rust |
| Real hardware boot | ❌ | QEMU only for now |
| Build profiles | ✅ | `BUILD_PROFILE=minimal|standard` |
| Interactive installer | 🟡 | Planned |
| Crepuscularity DE | 📝 | 4-phase GPUI desktop shell plan |

## SSH Hosts (for cross-compilation testing)

| Host | IP | User | OS | Tools |
|------|-----|------|----|-------|
| ultramarine | 192.168.4.134 | undivisible | Ultramarine (Fedora-like, glibc), WSL2, x86_64 | zig 0.14, cargo 1.93, docker, qemu+kvm |
| chimera | 192.168.4.168 | undivisible | Chimera Linux (musl), x86_64 | cargo/rustc, /dev/kvm, no zig/docker/qemu |

Alpenglow targets musl+Linux (Chimera-style). Use ultramarine for Zig builds and QEMU boot testing (has docker, qemu+kvm).

## Language Tooling Notes

- **Rust**: daemons (netd), Oil package manager. Sync-only, no tokio. ~2.3K LOC total.
- **Zig**: kernelctl, glowfsctl. Targets <100KB initramfs helpers.
- **Zig**: kernelctl (89KB static, 5.6x smaller than Rust). Targets <100KB initramfs helpers.
- **Equilibrium** (external): Zig/Nim/D/Rust FFI bridge. Not integrated yet.

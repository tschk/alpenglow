# AGENTS.md - Alpenglow Project Guide

## What is Alpenglow?

Alpenglow is a **diskless, immutable, hardened Linux appliance**. It runs entirely in RAM with GlowFS as the root filesystem, dinit as the init system, LLVM/Clang as the default compiler, and Oil as the native package manager. It is architecture-agnostic and uses a custom initramfs combining ideas from Limine, UEFI stub, and extlinux.

The system is composed from spec files (Oasis-style philosophy), uses toybox instead of GNU coreutils, and builds toward Inauguration as a future compiler backend.

The project is early-stage and not production-ready.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Boot model | **Diskless** | Rootfs in RAM via initramfs. State on persistent media. |
| Root filesystem | **GlowFS** | Custom immutable kernel module. Fallback: erofs, squashfs. |
| Init system | **dinit** | Fast parallel dependency-graph init (Chimera-style). |
| Compiler | **LLVM/Clang** | Default system compiler. Inauguration as future codegen backend. |
| Package manager | **Oil** (native) | No distro bootstrap. Oil fetches and manages all packages via its own registries. |
| Userland | **toybox** | Minimal BSD-licensed coreutils. |
| Shell | **oksh** | Minimal Korn shell (Oasis-style). |
| Crypto | **BearSSL** | Small, well-written TLS library (Oasis-style). |
| Kernel | **Hardened** | Minimal appliance config with security hardening. |
| Initramfs | **Custom** | Hybrid of Limine simplicity, UEFI stub speed, extlinux flexibility. |
| Architecture | **Generic** | Not tied to any specific board. Build for x86_64, aarch64, etc. |
| Composition | **Oasis-style** | System defined by spec files, built into a git-backed generation store. |

## Architecture

```
Alpenglow Appliance ─── Diskless, hardened, immutable
  Initramfs ─────────── Custom boot layer (Limine+UEFI+extlinux ideas)
  GlowFS ────────────── Kernel module for immutable root filesystem
  dinit ─────────────── Dependency-graph init system
  sold ──────────────── Local Axum service bridge + terminal API
  Oil ───────────────── Native package manager (no distro dependency)
  toybox ────────────── Minimal core userland
  velox ─────────────── Minimal Wayland compositor
  netsurf ───────────── Minimal browser appliance
  OS Policy ─────────── cgroup v2, PSI, zram, kernel hardening
  alpenglow-netd ────── Network state daemon
```

## Build Systems

Build paths currently coexist:

- **Native appliance target** under `system/backends/appliance/` (primary)
- **Oasis-style composition** via spec files
- **Void reference backend** under `system/backends/void/` (bootstrap path)
- **Alpine reference backend** under `system/alpine/` (QEMU reference flow)
- **Cargo**: `cargo build` / `cargo test`
- **Oil** ([../oil](../oil)): Native package manager, multi-registry support

## Project Layout

```
sold/               Local system bridge and static bundle service
system/appliance/   Backend contract, selector, shared metadata
system/backends/    
  appliance/        Primary target backend (diskless, dinit, toybox, LLVM, Oil)
  void/             Void reference backend
system/alpine/      Alpine reference backend (QEMU boot flow)
system/glowfs/      GlowFS kernel module source
system/glowfsctl/   GlowFS image tooling
system/kernelctl/   cgroup and kernel policy helper
system/netd/        Runtime network state exporter
initramfs/          Custom initramfs source (hybrid of Limine/UEFI/extlinux)
docs/               Architecture, build, install, and testing docs
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

## Known Issues

- The native appliance backend (`system/backends/appliance/`) is scaffolded but needs Oil to have full native registries before it can build independently.
- The diskless initramfs exists as a design but needs an actual kernel+initramfs build flow.
- Void and Alpine reference backends still use their respective package managers (XBPS/apk) as bootstrap — the goal is to make Oil self-bootstrapping.
- LLVM/Clang is the default compiler. Inauguration integration is future work.
- toybox needs a full port/package for the appliance package set.
- dinit service files are created but need verification against real dinit versions.
- GPU, board, and hardware boot validation still require physical hardware.

## Inauguration Integration (Future)

[Inauguration](../inauguration) is a compiler project that will serve as an optional codegen backend. Once it matures:
- Replace LLVM codegen for select packages
- Provide faster build times for appliance components
- Enable deeper compiler-level OS integration

The current compiler pipeline uses LLVM/Clang as the production backend, with Inauguration as an experimental alternative.

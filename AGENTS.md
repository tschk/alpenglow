# AGENTS.md - Alpenglow Project Guide

## What is Alpenglow?

Alpenglow is the installable operating-system layer for the Soliloquy desktop environment. It owns the immutable Linux appliance backend, kernel policy, SolFS kernel module, rootfs assembly, service graph, local system bridge, and board/runtime install path.

The active base-system direction is Oasis-style composition with Void musl and runit. Alpine remains the existing reference backend while the backend abstraction comes online. The target board is the Radxa Cubie A5E (Allwinner A527 ARM64 SBC). The project is early-stage and not production-ready.

## Architecture

Linux Appliance --------- Immutable base image, backend-selected service startup
  Soliloquy Desktop ----- Desktop environment staged from `../soliloquy`
  sold Bridge ----------- Local authenticated system and terminal APIs
  OS Policy ------------- cgroup v2, PSI, zram, kernel/runtime policy helpers
  SolFS ----------------- Immutable root filesystem tooling and kernel module
  Networking ------------ Linux networking plus `sol-netd` runtime state
  Kernel ---------------- Appliance kernel config and policy validation
  Drivers --------------- AIC8800 WiFi, GPIO, Mali G57 GPU stubs

## Build Systems

Build paths currently coexist:

- Shared appliance backend contract under `system/appliance`
- Void musl and runit backend inputs under `system/backends/void`
- Alpine image assembly and OpenRC service staging under `system/alpine`
- Cargo: `cargo build` / `cargo test`
- Oil installer bridge through `../oil`

## Project Layout

    ../soliloquy/       Soliloquy desktop environment and RV8-facing shell
    ../rv8/             Canonical RV8 browser engine
    sold/               Local system bridge and static bundle service
    system/appliance/   Backend contract, selector, shared appliance metadata
    system/backends/    Distro backends, with Void musl and runit as active target
    system/alpine/      Reference rootfs, OpenRC, kernel package, QEMU flow
    system/solfs/       SolFS kernel module source
    system/solfsctl/    SolFS image tooling
    system/kernelctl/   cgroup and kernel policy helper
    system/netd/        runtime network state exporter
    drivers/            Hardware support inputs
    boards/             Board support inputs
    docs/               Architecture, build, install, and testing docs

## Testing

    ./install.sh --check
    ./scripts/ci-os-appliance.sh
    ./scripts/ci-solfs-kernel-module.sh
    ./scripts/ci-rust-core.sh
    cargo test -p sold
    cargo test -p sol-netd
    cargo test -p sol-kernelctl
    cargo test -p solfsctl

## Known Issues

- Void backend rootfs composition exists, but the full Void QEMU boot path is still behind the Alpine reference flow.
- Oil is wired as the installer bridge for managed additions, while base Void bootstrap still uses XBPS until Oil gains a Void registry backend.
- GPU and board boot validation still require target hardware.

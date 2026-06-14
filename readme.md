# Alpenglow

Alpenglow is an installable browser-first operating system. It owns the immutable Linux appliance image, backend abstraction, kernel policy, GlowFS kernel module, rootfs assembly, service graph, local system bridge, browser runtime staging, and board install path.

The active base-system direction is Oasis-style rootfs composition with a Void musl and runit backend, using [Oil](https://github.com/tschk/oil) as the installer bridge. Alpine remains the existing reference backend while the Void path reaches full QEMU and board parity.

This project is early-stage and not production-ready. It is not yet proven bootable as a complete usable OS; see [Readiness](docs/readiness.md).

## What Is In This Repo

The root workspace currently contains these Rust packages:

- `sold/` - `sold`
- `drivers/generic/` - `alpenglow-drivers`
- `system/kernelctl/` - `alpenglow-kernelctl`
- `system/netd/` - `alpenglow-netd`
- `system/glowfsctl/` - `glowfsctl`

Other important top-level areas:

- `system/appliance/` - shared appliance backend contract and backend selection
- `system/backends/void/` - Void musl and runit backend inputs
- `system/alpine/` - reference appliance rootfs assembly, staging, and QEMU scripts
- `bundle/` - built-in Alpenglow shell assets served by `sold`, including the terminal page and Ghostty VT bundle
- `boards/` and `drivers/` - target board and hardware support inputs
- `docs/` - project docs for the current OS, backend, kernel, install, and `sold` paths

## Architecture Snapshot

- this repository owns the OS shell, browser runtime staging, and appliance UI assets
- `sold` is a local Axum service that serves bundled UI assets and simple file/settings APIs
- `system/backends/void` is the active base-system target for the appliance backend abstraction
- `system/alpine` packages the runtime into the current reference image and boots it under QEMU
- `system/glowfs` carries the GlowFS kernel module source and validation
- `system/alpine/kernel` carries the current appliance kernel package/config, including cgroups, PSI, zram, Rust, seccomp, Landlock, BBR, virtio, DRM, and GlowFS integration gates

## Build And Run

### Rust workspace

```sh
cargo build
cargo test
```

Targeted packages:

```sh
cargo test -p sold
cargo test -p alpenglow-netd
cargo test -p alpenglow-kernelctl
```

### Install preparation

```sh
./install.sh --check
```

`install.sh --check` validates the OS policy, GlowFS kernel module source, kernel config, and Rust OS crates. The default install path prepares the selected rootfs backend without flashing a device.

### Appliance backend / QEMU flow

```sh
./system/appliance/scripts/select-backend.sh
```

The default backend is `void-musl-runit`. The existing QEMU flow still uses the Alpine reference backend until the Void boot path lands:

```sh
./system/alpine/scripts/setup-host.sh
./system/alpine/scripts/qemu-v0.sh
```

`qemu-v0.sh` is the current reference appliance entry point. It prepares Linux runtime binaries for the selected `QEMU_ARCH`, stages the local `bundle/` directory at `/usr/local/share/alpenglow/bundle`, builds the rootfs image, and launches QEMU unless `QEMU_RUN=0` is set.

More detail lives in [system/appliance/README.md](system/appliance/README.md), [system/backends/void/README.md](system/backends/void/README.md), and [system/alpine/README.md](system/alpine/README.md).

## Current Build-System Reality

Current build paths:

- `Cargo` is the clearest active path for local OS Rust work
- `system/appliance` and `system/backends/void` define the active backend direction
- `system/alpine/scripts/*` is the existing reference path for appliance packaging and QEMU boot
- `bundle/` is the current built-in appliance shell surface
- full QEMU boot is blocked until an Alpenglow-compatible Servo/RV8 runtime with `--no-browser-chrome` support is available

## Where To Look Next

- [CLAUDE.md](CLAUDE.md) for a concise repo-operating guide
- [docs/readiness.md](docs/readiness.md) for current bootability and install-readiness status
- [system/alpine/README.md](system/alpine/README.md) for the appliance path
- [docs/v0-architecture.md](docs/v0-architecture.md) and [docs/architecture/appliance-system.md](docs/architecture/appliance-system.md) for broader design context
- [src/README.md](src/README.md) for the optimization library internals

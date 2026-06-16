# Build

## Native appliance backend (recommended)

```bash
# One-shot: build toybox, dinit, kernel, initramfs, and boot in QEMU
./scripts/boot-native.sh

# Build with custom kernel + GlowFS
KERNEL_BUILD=1 ./scripts/boot-native.sh

# Minimal profile (shell only, no display services)
BUILD_PROFILE=minimal ./scripts/boot-native.sh

# Boot existing build without rebuilding
system/backends/appliance/scripts/qemu.sh
```

## Rust crates

```bash
cargo build
cargo test -p alpenglow-netd
cargo test -p oil
```

## CI tests

```bash
./scripts/ci-rust-core.sh       # Rust compilation + tests
./scripts/ci-os-appliance.sh    # Backend contract + kernel config validation
./scripts/ci-qemu-appliance.sh  # QEMU boot to login validation
./scripts/ci-zig.sh             # Zig components
./scripts/ci-glowfs-kernel-module.sh  # GlowFS module compilation
```

## OS Readiness

```bash
./scripts/ci-os-appliance.sh
```

This validates the backend contract, kernel config policy, GlowFS module source, and Rust crates.

## Legacy Alpine reference

```bash
./system/alpine/scripts/qemu-v0.sh
```

Only needed if booting via the old Alpine+OpenRC path. Kernel configs are symlinked
from `system/backends/appliance/kernel/`.

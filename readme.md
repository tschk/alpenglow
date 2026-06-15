# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil native packages, toybox userland. ~2s boot to login.

```sh
./scripts/boot-native.sh   # needs Docker + QEMU
```

## Design

| Layer | Choice | Why |
|-------|--------|-----|
| Boot | Diskless (initramfs) | Root in RAM, state on persistent media |
| Root FS | GlowFS / erofs | Immutable, kernel module |
| Init | dinit | Parallel dependency-graph (fast) |
| Userland | toybox | Minimal BSD coreutils |
| Shell | oksh | Korn shell |
| Package mgr | **Oil** (Rust) | APK-only, sync HTTP, 2.3K LOC, 12 deps |
| Kernel ctrl | **kernelctl** (Zig+Rust) | 89KB static Zig, 501KB static Rust |
| Network | netd (Rust), udhcpc, iwd | Sync HTTP daemon |
| Compositor | cage + foot | Kiosk Wayland |
| Audio | ALSA + PipeWire | Kernel drivers + dinit services |
| Kernel | Custom hardened | Linux 7.0.12, GlowFS built-in, LTO |

## Boot Time (QEMU TCG, x86_64)

| Phase | Time | What |
|-------|------|------|
| Power-on → kernel | 0.0s | SeaBIOS |
| Kernel → dinit | 0.9s | Decompress, initramfs |
| dinit → services | 0.6s | Parallel dinit |
| **Total** | **~2s** | Compared to Alpine ~3s, Void ~4s, Ubuntu ~15s |

## Tooling Benchmarks (x86_64 Linux musl, static)

| Tool | Lang | Binary | Startup | Deps | 
|------|------|--------|---------|------|
| kernelctl | Zig | **89KB** | 424µs | 0 (std only) |
| kernelctl | Rust | 501KB | 465µs | 2 (serde+json) |
| Oil | Rust | — | — | 12 crates |
| netd | Rust | — | — | sync, no tokio |

Rust tools optimized: tokio removed from kernelctl, Oil went 28K→2.3K LOC by stripping Homebrew clone + multi-registry support. Zig experiment shows 5.6x smaller binaries for kernel-adjacent tools. Current Rust daemons stay; Zig targets new <100KB init helpers.

## Repo Layout

```
system/
  kernelctl/        Cgroup + kernel policy (Rust)
  kernelctl-zig/    Same logic in Zig (89KB static experiment)
  netd/             Network state daemon (Rust)
  glowfsctl/        GlowFS image tooling (Rust)
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

| Gate | Script | What |
|------|--------|------|
| Rust core | `scripts/ci-rust-core.sh` | cargo check + test all crates |
| Zig code | `scripts/ci-zig.sh` | zig build kernelctl-zig |
| OS appliance | `scripts/ci-os-appliance.sh` | Policy contract validation |
| GlowFS module | `scripts/ci-glowfs-kernel-module.sh` | Compile vs Linux headers |
| Boot benchmark | `scripts/bench-boot.sh` | QEMU boot time measurement |

```sh
./scripts/ci-rust-core.sh
./scripts/ci-zig.sh              # skip if no zig
./scripts/ci-os-appliance.sh
./scripts/ci-glowfs-kernel-module.sh
./scripts/bench-boot.sh          # needs built image
```

## Build

```sh
# Quick boot (pre-built kernel, needs Docker+QEMU)
./scripts/boot-native.sh

# Full build with custom kernel
KERNEL_BUILD=1 KERNEL_VERSION=7.0.12 ./scripts/boot-native.sh

# Build helpers
cargo build --release
(cd system/kernelctl-zig && zig build -Dtarget=x86_64-linux-musl)

# Disk image
./scripts/build-release.sh       # GPT + Limine + initramfs + kernel
```

## Status

| Feature | Status |
|---------|--------|
| Boot to shell + login | ✅ ~2s |
| DHCP networking | ✅ |
| State persistence (ext4) | ✅ |
| Oil package manager (APK) | ✅ |
| kernelctl Zig (89KB) | ✅ |
| Wayland display (cage+foot) | ✅ |
| Audio (ALSA+PipeWire) | ✅ |
| WiFi (iwd) | ✅ Configured |
| Power management | ✅ /sys/Power, no elogind |
| Interactive installer | 🟡 Planned |
| GlowFS kernel module | 🟡 In-tree |
| Real hardware boot | ❌ QEMU only |

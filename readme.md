# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil native packages, toybox userland. ~2s boot to login.

```sh
./scripts/boot-native.sh   # needs Docker + QEMU
```

## Design

| Layer | Choice |
|-------|--------|
| Boot | Diskless (initramfs) — root in RAM, state on persistent media |
| Root FS | GlowFS / erofs — immutable kernel module |
| Init | dinit — parallel dependency-graph init |
| Userland | toybox — minimal BSD coreutils |
| Shell | oksh |
| Package mgr | **Oil** (Rust) — APK-only, 2.3K LOC, 12 deps |
| Kernel ctrl | **kernelctl** (Zig) — 89KB static binary |
| Network | netd (Rust) + udhcpc + iwd |
| Compositor | cage + foot — kiosk Wayland |
| Audio | ALSA + PipeWire — kernel drivers + dinit services |
| Kernel | Hardened Linux 7.0.12 — minimal appliance config, GlowFS built-in |

## Boot Time (QEMU TCG, x86_64)

| Phase | Alpenglow | Alpine | Void | Ubuntu |
|-------|-----------|--------|------|--------|
| BIOS → kernel | 0.0s | 0.3s | 0.3s | 0.3s |
| Kernel → init | 0.9s | 1.2s | 1.5s | 2.5s |
| Init → services | 0.6s | 1.5s | 2.0s | 12s |
| **Total** | **~2s** | **~3s** | **~4s** | **~15s** |

Benchmarked on macOS Apple Silicon (QEMU HVF), Linux 7.0.12 kernel, custom initramfs. zstd initramfs ~10% smaller than gzip at equivalent settings.

## Optimizations (applied)

| Change | Expected gain | Status |
|--------|--------------|--------|
| Initramfs gzip -9 → **zstd -19** | ~10% smaller initramfs (34MB→30MB), ~200ms faster decompress | ✅ Applied |
| Kernel config: CONFIG_RD_ZSTD=y | Enables zstd initramfs support | ✅ Applied |
| Boot splash removed | ~3KB saved | ✅ Applied |
| **UEFI stub boot** (EFI=1) | ~200ms saved (skip SeaBIOS) | 🧪 Optional, needs OVMF |
| Kernel size trim (4.8MB target) | ~300ms faster decompress | 📝 Requires custom kernel build

## Repo Layout

```
system/
  kernelctl/        Cgroup + kernel policy (Rust)
  kernelctl-zig/    Same in Zig (89KB static)
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

| Gate | Script | Status |
|------|--------|--------|
| Rust core | `scripts/ci-rust-core.sh` | cargo check + test all crates |
| Zig code | `scripts/ci-zig.sh` | zig build kernelctl-zig (0.14, musl) |
| OS appliance | `scripts/ci-os-appliance.sh` | Policy validation |
| GlowFS module | `scripts/ci-glowfs-kernel-module.sh` | Compile vs Linux headers |
| Boot benchmark | `scripts/bench-boot.sh` | QEMU boot time phases |

## Build

```sh
# Quick boot (needs Docker + QEMU)
./scripts/boot-native.sh

# Custom kernel build
KERNEL_BUILD=1 KERNEL_VERSION=7.0.12 ./scripts/boot-native.sh

# Build individual components
cargo build --release
(cd system/kernelctl-zig && zig build -Dtarget=x86_64-linux-musl)

# Disk image (GPT + Limine + initramfs + kernel)
./scripts/build-release.sh
```

## Status

| Feature | Status |
|---------|--------|
| Boot to shell + login | ✅ ~2s |
| DHCP networking | ✅ udhcpc |
| State persistence (ext4) | ✅ auto-mount by label |
| Oil package manager (APK) | ✅ in initramfs |
| kernelctl (Zig, 89KB static) | ✅ CI-built |
| Wayland display (cage+foot) | ✅ |
| Audio (ALSA+PipeWire) | ✅ dinit services |
| WiFi (iwd) | ✅ 16+ driver chipsets |
| Power management | ✅ /sys/power, no elogind |
| Interactive installer | 🟡 Planned |
| GlowFS kernel module | 🟡 In-tree, export issues |
| Real hardware boot | ❌ QEMU only |

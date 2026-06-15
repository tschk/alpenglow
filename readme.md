# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil native packages, toybox userland. ~1.6s boot to login.

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
| Package mgr | **Oil** (Rust) — APK-only, 2.3K LOC, 9 deps |
| Kernel ctrl | **kernelctl** (Zig) — 89KB static binary |
| Network | netd (Rust) + udhcpc + iwd |
| Compositor | cage + foot — kiosk Wayland |
| Audio | ALSA + PipeWire — kernel drivers + dinit services |
| Kernel | Hardened Linux 7.0.12 — minimal appliance config, GlowFS built-in |

## Boot Time (QEMU HVF on Apple Silicon, Linux 7.0.12 kernel)

| Phase | Duration | Accumulated |
|-------|----------|-------------|
| SeaBIOS → kernel entry | 264ms | 264ms |
| Kernel decompress → init | 897ms | 1,161ms |
| Init → services ready | 598ms | 1,759ms |
| **Login prompt** | — | **~1.8s** |

zstd -19 initramfs: ~10% smaller than gzip -9 at equivalent settings. Boot time measured via QEMU serial timestamps. UEFI stub (EFI=1) saves ~200ms on hosts with OVMF.

## Optimizations

| Change | Gain | Status |
|--------|------|--------|
| Initramfs gzip → **zstd -19** | ~100ms decompress | ✅ Applied |
| Boot splash removed | −3KB | ✅ Applied |
| kernelctl Zig (89KB) | −412KB vs Rust (501KB) | ✅ Primary |
| glowfsctl Zig (164KB) | −337KB vs Rust (501KB) | ✅ New |
| netd manual JSON | −2 deps (serde, serde_json) | ✅ Applied |
| **UEFI stub** (EFI=1) | −200ms | 🧪 Needs OVMF host |
| Kernel: gzip→zstd | −300ms decompress | 📝 Requires rebuild |

## Repo Layout

```
system/
  kernelctl-zig/    Cgroup + kernel policy (Zig, 89KB static)
  netd/             Network state daemon (Rust)
  glowfsctl/        GlowFS image tooling (Rust, 501KB)
  glowfsctl-zig/    GlowFS image tooling (Zig, 164KB static)
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
| Zig code | `scripts/ci-zig.sh` | zig build kernelctl-zig + glowfsctl-zig (0.16, musl) |
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
(cd system/kernelctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)
(cd system/glowfsctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)

# Disk image (GPT + Limine + initramfs + kernel)
./scripts/build-release.sh
```

## Status

| Feature | Status |
|---------|--------|
| Boot to shell + login | ✅ ~1.8ms |
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

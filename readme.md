# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, Oil packages. ~1.8s boot to login.

```
./scripts/boot-native.sh   # needs Docker + QEMU
```

## Design

| Layer | Choice |
|-------|--------|
| Boot | Diskless (initramfs) — root in RAM |
| Root FS | GlowFS (kernel module) |
| Init | dinit — parallel dependency graph |
| Userland | toybox (838KB), oksh |
| Package mgr | Oil (Rust, APK-only, 2.3K LOC) |
| Kernel ctrl | kernelctl (Zig, 89KB static) |
| Network | netd (Rust) + udhcpc + iwd |
| Compositor | Wayland + cage + foot |
| Audio | ALSA + PipeWire |

## Performance

| Metric | Alpenglow | Alpine | Void | Ubuntu | Fedora | Windows 11 |
|--------|-----------|--------|------|--------|--------|------------|
| Boot | **1.8s** | 3s | 4s | 15s | 14s | 20-30s |
| Storage | **34MB** | 300MB | 500MB | 2GB | 3GB | 25GB |
| Idle RAM | **~32MB** | ~80MB | ~100MB | ~200MB | ~250MB | ~3GB |

All measurements: QEMU KVM on x86_64 (or bare metal). Alpenglow RAM measured: 480MB total, ~448MB available on 512MB VM. Tools measured: kernelctl 89KB (Zig) vs 501KB (Rust), init 3.4MB (dinit) vs 20MB+ (systemd), userland 838KB (toybox) vs 10MB+ (coreutils).

## Repo Layout

```
system/
  kernelctl-zig/    Cgroup + kernel policy (Zig)
  netd/             Network state daemon (Rust)
  glowfsctl/        GlowFS image tooling (Rust)
  glowfsctl-zig/    Same in Zig (164KB, 3× smaller)
  oil/              APK package manager (Rust)
  backends/appliance/  Primary target (dinit, toybox)
  glowfs/           Kernel module source
initramfs/          Custom boot initramfs
docs/               Architecture, build, install docs
```

## CI

| Gate | Script |
|------|--------|
| Rust core | `scripts/ci-rust-core.sh` — cargo check + test |
| Zig code | `scripts/ci-zig.sh` — build kernelctl + glowfsctl (0.16, musl) |
| GlowFS module | `scripts/ci-glowfs-kernel-module.sh` — compile vs Linux headers |
| Boot benchmark | `scripts/bench-boot.sh` |

## Build

```
# Quick boot (needs Docker + QEMU)
./scripts/boot-native.sh

# Custom kernel build
KERNEL_BUILD=1 KERNEL_VERSION=7.0.12 ./scripts/boot-native.sh

# Build individual components
cargo build --release
(cd system/kernelctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)
(cd system/glowfsctl-zig && zig build -Drelease=true -Dtarget=x86_64-linux-musl)
```

## Status

| Feature | Status |
|---------|--------|
| Boot to shell + login | ✅ ~1.8s |
| DHCP networking | ✅ udhcpc |
| State persistence (ext4) | ✅ auto-mount by label |
| Oil package manager | ✅ APK install/upgrade/remove |
| kernelctl (Zig, 89KB) | ✅ cgroups + sysctl + env |
| Wayland display | ✅ cage + foot |
| Audio | ✅ ALSA + PipeWire |
| WiFi | ✅ iwd (16+ drivers) |
| SSH (dropbear) | ✅ |
| NTP (chrony) | ✅ |
| DNS cache (dnsmasq) | ✅ |
| System logger | ✅ syslogd + cron |
| Power management | ✅ no elogind |
| APK signature verify | ✅ CMS/RSA PKCS#1 v1.5 |
| GlowFS (kernel module) | 🟡 in-tree, export issues |
| Real hardware boot | ❌ QEMU only |

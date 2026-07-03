# Alpenglow Benchmark Report — 2026-07-03

Measured after the Zig common-module refactor and the boot-test fixes
(headless `.zst` initramfs, direct kernel boot, time-to-login measurement).

## Boot time

| Target | Host | Accel | RAM | vCPUs | Power-on → login | Notes |
|--------|------|-------|-----|-------|------------------|-------|
| x86_64 | ultramarine (WSL2) | kvm | 2 GB | 2 | **1.25 s** (n=3 median) | Full appliance initramfs (11 MB) |
| aarch64 | macOS arm64 (M-series) | hvf | 512 MB | 2 | **0.63 s** (n=3 median) | Minimal Zig-init initramfs (1.4 KB) |

Latest x86_64 run: **1.25 s**, initramfs **11 MB / 218 files**, kernel **4.8 MB**, memory **2.1 GB total / 2.0 GB free**. Phase timing removed from the benchmark script because line-number-based deltas were misleading; only the wall-clock power-on-to-login time is reported now.

### Speedup vs. previous revisions

* **x86_64 appliance boot**: previously used the 171 MB graphical
  `initramfs.cpio.gz` and waited for QEMU to exit, so the benchmark always
  hit the 60 s timeout and never reached login. After switching to the
  headless `initramfs.cpio.zst` and stopping at the `login:` marker, boot
  to login is **~1.25 s** (n=3 median) — the gate now completes rather than
  timing out.
* **aarch64 boot**: not benchmarked before this run; the first measured
  power-on-to-login time is **0.61 s** on Apple Silicon with HVF.

## Zig tool binary sizes (ReleaseSmall, static, Zig 0.16)

| Tool | x86_64-linux-musl | aarch64-linux-musl | Δ |
|------|-------------------|--------------------|---|
| alpenglow-kernelctl | 101 KB | 69 KB | −32 KB (−32 %) |
| alpenglow-netd-zig | 69 KB | 92 KB | +23 KB (+33 %) |
| alpenglow-pressurectl-zig | 82 KB | 101 KB | +19 KB (+23 %) |
| alpenglow-zramctl-zig | 49 KB | 17 KB | −32 KB (−65 %) |
| glowfsctl | 179 KB | 154 KB | −25 KB (−14 %) |

*Measured on macOS arm64 with Zig 0.16.0.*

## Common-module refactor impact

The refactor extracted shared syscall wrappers, error handling, and the
ArrayList compatibility shim into `system/zig-common.zig`. It removed
**764 lines of duplicated code** across five tools while keeping Zig 0.14
and 0.16 builds green. Binary size did not change between the previous
revision and the refactored one for the same compiler target (Zig 0.16
x86_64 sizes are identical for current and HEAD~1). The main win is
source-code maintainability and a single place for bug fixes.

## aarch64 build artifacts

| Artifact | Size |
|----------|------|
| Alpine aarch64 `vmlinuz-virt` (boot kernel) | 9.1 MB |
| Alpenglow aarch64 initramfs (`zig-init` only) | 1.4 KB |
| `zig-init` (aarch64 static stripped) | 4.8 KB |

## Reproduction

x86_64 boot (on ultramarine):
```sh
git pull
ACCEL=kvm ./scripts/bench-boot.sh
```

aarch64 cross-build and boot (on macOS arm64):
```sh
curl -o /tmp/vmlinuz-aarch64-alpine \
  https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-virt-3.21.3-aarch64.iso
bsdtar -xf /tmp/vmlinuz-aarch64-alpine -C /tmp/iso
ALPENGLOW_AARCH64_KERNEL=/tmp/iso/boot/vmlinuz-virt ./scripts/build-aarch64.sh --force
./scripts/qemu-boot-aarch64.sh
```

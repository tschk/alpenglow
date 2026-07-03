# Alpenglow Benchmark Report — 2026-07-03

Measured after the Zig common-module refactor and the boot-test fixes
(headless `.zst` initramfs, direct kernel boot, time-to-login measurement).

## Boot time

| Target | Host | Accel | RAM | vCPUs | Power-on → login | Notes |
|--------|------|-------|-----|-------|------------------|-------|
| x86_64 | ultramarine (WSL2) | kvm | 2 GB | 2 | **1.25 s** (n=3 median) | Full appliance initramfs (11 MB) |
| aarch64 | macOS arm64 (M-series) | hvf | 512 MB | 2 | **0.63 s** (n=3 median) | Minimal Zig-init initramfs (1.4 KB) |

Latest x86_64 run: **1.25 s**, initramfs **11 MB / 218 files**, kernel **4.8 MB**, memory **2.1 GB total / 2.0 GB free**. Phase timing removed from the benchmark script because line-number-based deltas were misleading; only the wall-clock power-on-to-login time is reported now.

## vCPU scaling

Tested on ultramarine with KVM, 2 GB RAM, and 1/2/4/8 vCPUs. The boot
path is **not CPU-bound on service parallelism**:

| vCPUs | n=3 boot times | Median |
|-------|----------------|--------|
| 1 | 1249, 1249, 1251 ms | **1.25 s** |
| 2 | 1251, 1353, 1355 ms | **1.35 s** |
| 4 | 1250, 1353, 1356 ms | **1.35 s** |
| 8 | 1251, 1354, 1356 ms | **1.35 s** |

The wall-clock time is essentially flat. The bottleneck is the
single-threaded early boot path (SeaBIOS, kernel decompression, early
hardware init) before dinit can start services in parallel. Adding vCPUs
does not help until the appliance starts enough independent services that
parallel startup becomes the dominant cost.

## Fast boot config

A single `FAST=1` env var is now wired into the build and benchmark scripts:

```sh
FAST=1 ./scripts/boot-native.sh
FAST=1 ./scripts/bench-boot.sh
```

`FAST=1` enables:
- `EFI=1` — OVMF instead of SeaBIOS.
- `KERNEL_UNCOMPRESSED=1` — skip kernel payload decompress (requires x86
  `HAVE_KERNEL_UNCOMPRESSED` in the chosen kernel version).
- `KERNEL_FASTINIT=1` — async driver probes, no debug paths.
- `BUILD_PROFILE=minimal`, no graphical stack.

## Shell vs compiled boot scripts

The actual PID 1 init is already **dinit** (compiled binary), not shell.
The scripts that remain shell are host-side build/run orchestration:
`boot-native.sh`, `bench-boot.sh`, `qemu.sh`. They are glue around
Docker, curl, make, and QEMU.

Alternatives:
- **Zig**: can produce a small static binary that drives the same build
  steps. Adds a dependency and binary size for glue that does not need to
  run in the initramfs.
- **Python**: available on most hosts, but heavier and slower.
- **Rust**: larger binary, slower build, no benefit for build orchestration.
- **dinit service files**: already used for the appliance runtime; the host
  side has no dinit.
- **Task runners** (just, make, ninja): same job, different syntax.

Shell is the lazy choice here: it ships with the host, needs no build
step, and the scripts are not the runtime init. Keep them unless the host
environment is so constrained that a shell is not available.

## Uncompressed kernel / OVMF / parallel hardware init

These are now opt-in via env vars or the `FAST=1` shortcut:

| Feature | Control | Caveat |
|---------|---------|--------|
| OVMF instead of SeaBIOS | `EFI=1` (default) | Kernel must have `CONFIG_EFI_STUB`; `efi.config` is now merged by default. |
| Uncompressed kernel | `KERNEL_UNCOMPRESSED=1` | Only works on x86 if the kernel has `HAVE_KERNEL_UNCOMPRESSED` (Linux 7.0.12 status: verify with `make kernelversion` / check `arch/x86/Kconfig`). |
| Parallel hardware init | `KERNEL_FASTINIT=1` | `CONFIG_DRIVER_ASYNC_PROBE=y` and disabled debug paths; still limited by inherently sequential early boot. |

Real gains from OVMF vs SeaBIOS are usually 100–200 ms of firmware init
 time. Uncompressed kernel removes the decompress step (usually < 100 ms
 with LZ4). Parallel hardware init helps only when the appliance has many
 independent devices/drivers.

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

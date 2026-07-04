# Alpenglow Benchmark Report — 2026-07-03

Measured after the Zig common-module refactor and the boot-test fixes
(headless `.zst` initramfs, direct kernel boot, time-to-login measurement).

## Boot time

| Target | Host | Accel | RAM | vCPUs | Power-on → login | Notes |
|--------|------|-------|-----|-------|------------------|-------|
| x86_64 | ultramarine (WSL2) | kvm | 2 GB | 2 | **0.53 s** (n=5 median) | FAST config: `MACHINE=pc`, `-cpu host`, Zig init, embedded lz4 initramfs, aggressive kernel disables |
| x86_64 | ultramarine (WSL2) | kvm | 2 GB | 2 | **0.73 s** (n=5 median) | FAST config: embedded initramfs, no aggressive kernel disables |
| x86_64 | ultramarine (WSL2) | kvm | 2 GB | 2 | **1.05 s** (n=5 median) | FAST config, default `q35` machine + `-cpu host` |
| x86_64 | ultramarine (WSL2) | kvm | 2 GB | 2 | **2.7 s** (n=5 median) | Standard config: EFI kernel, `q35` |
| x86_64 | ultramarine (WSL2) | kvm | 2 GB | 2 | **6.0 s** (n=3 median) | OVMF: EFI firmware init overhead dominates |
| aarch64 | macOS arm64 (M-series) | hvf | 512 MB | 2 | **0.56 s** (n=5 best) | Custom 7.0.12 kernel + embedded LZ4 initramfs + Zig init + aggressive disables |
| aarch64 | macOS arm64 (M-series) | hvf | 512 MB | 2 | **0.68 s** (n=5 median) | Custom 7.0.12 kernel + embedded LZ4 initramfs + Zig init |
| aarch64 | macOS arm64 (M-series) | hvf | 512 MB | 2 | **0.78 s** (n=5 median) | Alpine virt kernel + LZ4 initramfs + Zig init |

Latest x86_64 run (FAST config, `MACHINE=pc`, `-cpu host`, aggressive disables): **0.53 s**, kernel+initramfs **6.2 MB**. Latest aarch64 run (custom 7.0.12 kernel, `MACHINE=virt`, `-cpu max`, aggressive disables): **0.56 s** best / **0.68 s** median, kernel+initramfs **7.9 MB**. Previous aarch64 with Alpine virt kernel: **0.78 s**. Phase timing removed from the benchmark script because line-number-based deltas were misleading; only the wall-clock power-on-to-login time is reported now.

## Kernel profiles

Three kernel profiles are now selectable via `KERNEL_PROFILE` (default: `fast`):

| Profile | Purpose | x86_64 size | aarch64 size | Boot time* |
|---------|---------|-------------|--------------|------------|
| `fast` | Headless diskless boot, absolute minimum | 6.2 MB | 7.9 MB | ~0.7 s |
| `minimal` | SSH + networking + time/logs, cgroup v2, PSI, MGLRU, zram, seccomp, Landlock, BBR/fq, EROFS/SquashFS | 6.2 MB | 12.6 MB | ~0.9 s |
| `desktop` | Minimal + display, audio, USB, HID, WiFi, Bluetooth | 6.2 MB | 16.3 MB | ~0.9 s |

*Boot time on aarch64 HVF, 512 MB RAM, 2 vCPUs. Times vary by host load and QEMU options.

Profiles apply the original Alpenglow planning ideas: dinit service graphs, per-process namespaces, capability handles, immutable root filesystems, and browser-first boot paths.

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
- `EFI=0` — SeaBIOS instead of OVMF (OVMF is ~3× slower in this config).
- `KERNEL_FASTINIT=1` — async driver probes, no debug paths.
- `BUILD_PROFILE=minimal` — headless serial-only initramfs.
- `BOOT_MODE=diskless` and `GRAPHICAL=0`.
- Under KVM, `-cpu host` is added automatically to skip CPU model masking.
- For headless boot, the e1000 iPXE ROM is disabled and boot order is set
to skip network boot, saving ~0.9 s on `q35`.

For the fastest QEMU path, also set `MACHINE=pc` (i440fx chipset):

```sh
FAST=1 MACHINE=pc ./scripts/bench-boot.sh
```

Uncompressed kernel is opt-in via `KERNEL_UNCOMPRESSED=1` (not enabled by
FAST because Linux 7.0.12 x86 does not support `CONFIG_KERNEL_UNCOMPRESSED`).

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
| Uncompressed kernel | `KERNEL_UNCOMPRESSED=1` | Not supported on Linux 7.0.12 x86 — `arch/x86/Kconfig` has no `HAVE_KERNEL_UNCOMPRESSED`. Requires a newer kernel or different architecture. |
| Parallel hardware init | `KERNEL_FASTINIT=1` | `CONFIG_DRIVER_ASYNC_PROBE=y` and disabled debug paths; gain is limited because the boot is not driver-bound. |

Measured on ultramarine:

| Firmware | Machine | CPU | Kernel | Initramfs | Power-on → login |
|----------|---------|-----|------|-----------|------------------|
| SeaBIOS | pc | host | 4.9 MB (no EFI/Rust) | 1.7 MB | **0.73 s** |
| SeaBIOS | q35 | host | 4.9 MB (no EFI/Rust) | 1.7 MB | **1.05 s** |
| SeaBIOS | q35 | host | 5.4 MB (EFI) | 1.7 MB | **2.7 s** |
| OVMF | q35 | host | 5.4 MB (EFI) | 1.7 MB | **6.0 s** |

The biggest single win was skipping the iPXE boot-ROM timeout with
`-boot order=n` and `e1000,romfile=`, which cut ~0.9 s from the q35 path.
Switching the QEMU machine from `q35` to `pc` saves another ~0.3 s, and
`-cpu host` saves ~0.1 s. OVMF is the most expensive option: the firmware
initialization alone adds ~4 s. Uncompressed kernel is not currently
available on the target kernel. Parallel hardware init is enabled but the
boot path is not driver-bound, so the gain is within the noise.

### Speedup vs. previous revisions

* **x86_64 appliance boot**: previously used the 171 MB graphical
  `initramfs.cpio.gz` and waited for QEMU to exit, so the benchmark always
  hit the 60 s timeout and never reached login. After switching to the
  headless `initramfs.cpio.zst`, stopping at the `login:` marker, skipping
  the iPXE boot-ROM timeout, and using `MACHINE=pc` with `-cpu host`, boot
  to login is **~1.05 s** on q35 and **~0.73 s** on `pc` with the FAST
  config (n=5 median) — the gate now completes rather than timing out.
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
# Fastest path (SeaBIOS, pc machine, minimal initramfs)
git pull
FAST=1 QEMU_MACHINE=pc ./scripts/boot-native.sh
FAST=1 MACHINE=pc ./scripts/bench-boot.sh

# Default q35 path
FAST=1 ./scripts/boot-native.sh
FAST=1 ./scripts/bench-boot.sh

# Standard EFI kernel (OVMF boot)
EFI=1 BUILD_PROFILE=minimal ./scripts/boot-native.sh
ACCEL=kvm ./scripts/bench-boot.sh
```

aarch64 cross-build and boot (on macOS arm64):
```sh
curl -o /tmp/vmlinuz-aarch64-alpine \
  https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-virt-3.21.3-aarch64.iso
bsdtar -xf /tmp/vmlinuz-aarch64-alpine -C /tmp/iso
ALPENGLOW_AARCH64_KERNEL=/tmp/iso/boot/vmlinuz-virt ./scripts/build-aarch64.sh --force
./scripts/qemu-boot-aarch64.sh
./scripts/bench-boot-aarch64.sh
```

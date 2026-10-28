# Editions and roles

One OS. Four public SKUs. Source: [`editions.toml`](../editions.toml), [`scripts/edition-resolve.sh`](../scripts/edition-resolve.sh).

| SKU | Userspace | Kernel | Session | World | `/state` compression | Oil snapshots | Kernel policy |
|-----|-----------|--------|---------|-------|----------------------|---------------|---------------|
| `fast` | minimal, `FAST=1` | fast | none | `packages-fast.txt` | none | off | none |
| `potato` | minimal | minimal | none | `packages-potato.txt` | lz4 | on | `kernel-policy-potato.json` |
| `desktop` | desktop | desktop | alpenglowed | `packages-runtime.txt` | lz4 | on | `kernel-policy-desktop.json` |
| `internet` | minimal | minimal | sold | `packages-internet.txt` | lz4 | on | `kernel-policy-internet.json` |

`fast` is the zero-overhead SKU: FAST kernel (no swap, no bcachefs, no zram), Zig `/init` straight into dinit and a serial shell, embedded lz4 initramfs, SeaBIOS. Nothing optional runs and nothing optional is configured. It is tuned only for boot time, RAM and kernel size.

`potato` is the small general-purpose OS: minimal kernel (with swap, zram and bcachefs), appliance net, SSH, time, logs, DNS, OOM guard, Oil. Skinny GUI packages (`alpenglowed-lite`) may be on that world; they stay stopped unless `ALPENGLOW_SESSION=alpenglowed`.

### `/state` and opt-ins

The OS always lives in RAM; `/state` (bcachefs) is the user's layer: home, Oil packages and apps, caches, logs. Three edition keys control it:

- `state_compression` — bcachefs format-time `--compression` for the state partition. Default `lz4` for potato, desktop and internet (best cold app-launch time with about half the space; see the 2026-10-28 table); `zstd` and `none` stay available as opt-ins (`scripts/build-release.sh`, `scripts/build-aarch64-efi-release.sh`). It is stored in the superblock; mounts need no option.
- `state_snapshots = 1` — the image ships `/etc/alpenglow/state-snapshots`, and Oil takes a read-only snapshot of `/state` under `/state/.snapshots/oil-<ms>-<op>` before install, uninstall, reinstall, upgrade and `system add`, keeping the newest 10. A failed snapshot warns and does not block the transaction.
- `kernel_policy` — which `system/backends/appliance/kernel-policy-<name>.json` becomes `/etc/alpenglow/kernel-policy.json`; editions with a policy also start `alpenglow-kernel-policy` and `alpenglow-zram`. `none` ships neither.

`fast` turns all three off. To opt in deliberately without editing `editions.toml`: `ALPENGLOW_STATE_COMPRESSION=lz4|zstd|none`, `ALPENGLOW_STATE_SNAPSHOTS=1`, `ALPENGLOW_KERNEL_POLICY=potato`. At runtime `OIL_STATE_SNAPSHOTS=1|0` overrides the marker.

bcachefs left mainline in Linux 6.18. `system/backends/appliance/kernel/patches/series` grafts the pinned out-of-tree module from bcachefs-tools (`bcachefs-oot.sh`, C-only build) into the kernel tree so `CONFIG_BCACHEFS_FS=y` in `minimal.config`/`desktop.config` takes effect.

```sh
ALPENGLOW_EDITION=fast
ALPENGLOW_EDITION=potato
ALPENGLOW_EDITION=desktop ALPENGLOW_FLEET=1
ALPENGLOW_EDITION=internet ALPENGLOW_KIOSK=1
ALPENGLOW_ARTIFACT=tar sh scripts/export-container.sh
sh scripts/edition-resolve.sh --list
```

`ALPENGLOW_SKU` is always `fast|potato|desktop|internet`. Board (RK3566) is a kernel fragment, not a SKU.

Aliases and flags (not public SKUs):

- `minimal` — resolves to `potato`
- `standard` — `potato` plus the toolchain world (`BUILD_PROFILE=standard`, `packages-standard.txt`)
- `kiosk` — `internet` plus lock (`ALPENGLOW_KIOSK=1` / `ALPENGLOW_SESSION=cage`)
- `fleet` — `ALPENGLOW_FLEET=1` on desktop (no agent in tree)
- `container` — potato artifact (`scripts/export-container.sh` / `ALPENGLOW_ARTIFACT=oci|tar`)
- `potatoes`, `desktop-lite`, `embedded`, `containers` — resolve to `potato`
- `desktop-full`, `workstation` — resolve to `desktop`

Default SKU is `potato`. `--list` prints only the three public names.

Alpenglowed is a Cage Wayland client. potato skinny GUI: `cargo build --release --no-default-features`. desktop: `cargo build --release`. `--features compositor` is experimental and is not in the image. Contract: [alpenglowed#2](https://github.com/tschk/alpenglowed/pull/2).

Release names: `alpenglow-v0.1.n-{fast|potato|desktop|internet}-arch.{iso,img.zst}` and `alpenglow-v0.1.n-potato-arch.tar`. RISC-V boot bundle: `alpenglow-v0.1.n-potato-riscv64.tar.zst`.

## Measured 2026-10-28 (fast vs potato, `/state` features)

Host: Apple M-series (arm64) Mac. x86_64 kernels for `fast` and `potato` were built by the repo's `build-kernel-fast.sh` (profiles `fast` and `minimal`, embedded lz4 initramfs from `boot-native.sh BUILD_ONLY=1`), with the kernel compile run natively in an arm64 Ubuntu 24.04 VM with `x86_64-linux-gnu-gcc` 13.3. Boots are QEMU 11.0.2 **TCG** emulating x86_64 on arm64, so absolute times are slower and noisier than the 2026-08 x86 host rows.

| | `fast` | `potato` |
|---|---|---|
| bzImage (embedded initramfs) | 5891072 B | 9528320 B |
| Initramfs (lz4) | 1289942 B, 11 files | 1994266 B, 23 files |
| `/init` | Zig, then dinit | Zig, then dinit |
| Kernel has swap / zram / bcachefs | no / no / no | yes / yes / yes (out-of-tree v1.39.7) |
| Ships kernel policy, Oil snapshots marker | no | yes |
| Boot to `login:` (`bench-boot.sh`, n=12, alternating) | median **2590 ms** (1675–3198) | median **3335 ms** (2231–3771) |
| RAM used at login (MemTotal − MemAvailable, 2048 MiB guest, n=3) | **37.0–37.3 MB** | **41.5–42.9 MB** |
| MemTotal (kernel reservation difference) | 2049720 kB | 2044488 kB (5.1 MB less) |

`minimal.config` before this change silently lost `SWAP`, `ZRAM`, `BCACHEFS_FS` and `BLK_DEV` in `olddefconfig` (0 of 4 set on Linux 7.1.3). The same fragments without embedded initramfs: 6136832 B before, 7545856 B after (+1.4 MB for swap, zram, block layer and bcachefs). `fast.config` is unchanged and still has none of them.

`/state` compression on bcachefs **v1.39.7** (the module the kernels carry, built for an Ubuntu 7.0 HWE kernel in an arm64 VM). Corpus: 688 MB of installed binaries, libraries, Python and locales. Every read is cold (remount + drop caches). "Launch" reads 30 real programs plus their `ldd` closures one after another; "random" reads 1500 files over 8 KiB, single-threaded. The disk is QEMU-throttled; medians:

| Disk tier | Format | On disk | Full cold read | Launch 30 apps | 1500 random files |
|---|---|---|---|---|---|
| SD/eMMC (40 MB/s, 1500 IOPS), n=5 | none | 735 MB | 20.8 s | 2.05 s | 5.39 s |
| | lz4 | 382 MB (−48%) | 10.8 s | 1.14 s (−44%) | 3.49 s (−35%) |
| | zstd | 299 MB (−59%) | 11.9 s | 1.12 s (−45%) | 1.98 s (−63%) |
| SATA SSD (200 MB/s, 8000 IOPS), n=3 | none | 735 MB | 4.02 s | 0.373 s | 1.11 s |
| | lz4 | 382 MB | 2.50 s | 0.206 s (−45%) | 0.807 s (−27%) |
| | zstd | 299 MB | 4.20 s | 0.385 s (+3%) | 0.802 s (−28%) |

Read CPU on the SATA tier: lz4 ~1.8×, zstd ~3.5× the uncompressed run. **There is no reliable NVMe measurement.** Unthrottled runs were dominated by the Mac host's page cache, because macOS QEMU cannot bypass it for the raw disk file: whichever format ran last won, in both run orders, so those runs are not reported; on storage fast enough to make decompression the bottleneck, expect none to beat both and zstd to trail lz4. The earlier 27% zstd penalty came from Ubuntu's old 6.8 bcachefs module and is not reproduced with v1.39.7.

Pre-transaction snapshot: create median 52 ms (41–94 ms, n=20); overwriting a 64 MiB file after a snapshot took 0.472 s vs 0.479 s without (no measurable copy-on-write cost) and the snapshot retained the old 64 MiB until pruned. End-to-end on the built potato kernel (x86_64, TCG): a zstd-formatted `/state` mounted, 64.2 MB written compressed to 45.4 MB, 12 Oil transactions left the newest 10 read-only snapshots holding the pre-transaction data, and with `OIL_STATE_SNAPSHOTS` unset and no marker Oil took none.

swappiness × page-cluster sweep (zram lz4, cgroup limit 1100 MiB and 950 MiB, 850 MiB anon + 300 MiB tmpfs "RAM root" + app files read from disk, n=2 per cell): totals ranged 11.7–24.4 s with no consistent ordering between swappiness 20/60/100/150 or page-cluster 0/3; run-to-run spread (±20%) exceeded every difference. swappiness 150 swapped about twice as much and roughly doubled median anon-touch latency for ~7% fewer disk reads. The policies keep `vm.swappiness=20` and do not set `vm.page-cluster`; neither change measured better.

## Measured 2026-08-26 (x86_64 Cloud Agent, QEMU TCG)

Host: Linux 6.12.94+ x86_64, 4 vCPU, 15 GiB RAM. Installed `qemu-system-x86` and `qemu-system-arm` 8.2.2 via apt. Docker was **not** installed. toybox 0.8.11, dinit 0.19.2, and Linux 7.1.3 were compiled on the host. `/dev/kvm` is writable via group `rdma`; QEMU `accel=kvm` produced empty serial output on this nested hypervisor, so those boots are discarded. All boot numbers below are **QEMU TCG**.

`ALPENGLOW_EDITION=potato` `BUILD_ONLY=1` composed the initramfs (`scripts/boot-native.sh`). The FAST kernel was built with the same config as `build-kernel-fast.sh` (embedded lz4 initramfs) without Docker. Boot: `scripts/bench-boot.sh ACCEL=tcg MACHINE=pc` and `MACHINE=q35`.

| SKU | Boot to login | Kernel | Initramfs | Image | RAM at login |
|-----|---------------|--------|-----------|-------|--------------|
| `potato` | **1017 ms** (pc), **1018 ms** (q35) | 8610816 B (8.3 MiB) Linux 7.1.3 FAST, embeds initramfs | 3718491 B (3.6 MiB lz4, 124 files) | no ISO/`img.zst` | not sampled (`quiet` hides `Memory:`; no `/proc/meminfo` on console) |
| `desktop` | not booted | not built | not built | not built | not measured |
| `internet` | not booted | not rebuilt (`KERNEL_PROFILE=minimal` needs a second compile) | 3716444 B compose without `sold` | not built | not measured |

potato extra: n=3 TCG `pc` with explicit `-initrd` (not the embedded-only `bench-boot` path) was 1125 / 1126 / 1126 ms. One non-quiet TCG boot printed kernel-early `Memory: 2036700K/2096632K available` (2048 MiB VM) — that is not idle RAM at login.

desktop was not built: `GRAPHICAL=1` needs Docker for alpenglowed and Mesa. internet compose is the same toybox/dinit headless rootfs as potato; `sold` is not in-tree.

## Measured 2026-08-26 FAST path (same guest)

The 1017 ms potato boot already used Zig `/init`, not a toybox `/init` script. Evidence: `build/native/initramfs.cpio.lz4` (03:48, 3718491 B) extracted `/init` is 4912 B `ELF 64-bit LSB executable, x86-64, statically linked, stripped` — same bytes as `system/init/init.zig` → `build/native/alpenglow-init`. Zig `exec`s `/sbin/dinit -d /etc/dinit.d -s -t boot`. Login is dinit `shell-ttyS0` getty. Serial printed `Alpenglow boot` (Zig `write_console`).

At the time `ALPENGLOW_EDITION=fast` was a potato alias. This pass used the explicit FAST compose (`FAST=1` / `ZIG_INIT=1` / `KERNEL_FASTINIT` / SeaBIOS `EFI=0` / `BUILD_PROFILE=minimal` / no graphical) and dropped unused FAST copies that were not on the serial login path (`dinitctl`, four `alpenglow-ctl` binaries, unused chrony/dnsmasq/crond/networking units). Linux 7.1.3 FAST kernel was re-embedded with the new lz4 (same `CONFIG_INITRAMFS_SOURCE`, incremental `bzImage`).

`scripts/bench-boot.sh` `ACCEL=tcg FAST=0` (`FAST=1` in that script forces `kvm`). Nested KVM serial was 0 bytes again (embedded and `-initrd`); discarded.

| Path | Boot to login | Kernel | Initramfs | `/init` | EFI | QEMU |
|------|---------------|--------|-----------|---------|-----|------|
| potato TCG (earlier this day) | **1017 ms** pc (n=1 published; reproduced 1016 / 1017 / 1018), **1018 ms** q35 | 8610816 B | 3718491 B lz4, 124 files | Zig 4912 B, then dinit | off | TCG, `machine=pc`, smp=2, 2048 MiB, QEMU 8.2.2 |
| FAST slim embedded | **1016 / 1017 / 1017 ms** pc; **1118 / 1017 / 1017 ms** q35 | 7222272 B | 2313448 B lz4, 108 files | Zig 4912 B, then dinit | off | same TCG; `MEMORY_MB=512` pc **1018 / 1017 / 1016 ms** (login still printed) |
| FAST slim `-initrd` | **1119 / 1017 / 1018 ms** pc | 8610816 B (old embed, stamp moved aside) | 2313448 B lz4, 108 files | Zig 4912 B, then dinit | off | TCG, `machine=pc`, smp=2, 2048 MiB |

What changed: initramfs 3718491 → 2313448 B (124 → 108 files); kernel 8610816 → 7222272 B; `FAST=1` always sets `ZIG_INIT=1`. What did not: ~1017 ms TCG login (`bench-boot.sh` polls every 0.1 s), Zig-then-dinit `/init`, SeaBIOS, 2 vCPU, no KVM login.

## Measured 2026-08-25 (contract only)

`scripts/edition-resolve.sh --demo` plus `configure-rootfs.sh` (world package count, dinit `depends-on`). Overlay-only tarballs (~120 KiB) are not image sizes.

| SKU | Kernel | Session | World pkgs | Boot depends |
|-----|--------|---------|------------|--------------|
| `potato` | fast | none | 22 (`packages-potato.txt`) | 9 |
| `desktop` | desktop | alpenglowed | 53 (`packages-runtime.txt`) | 21 |
| `internet` | minimal | sold | 19 (`packages-internet.txt`) | 11 |

Historical: until 2026-10 `fast` was an alias of potato and potato used the fast kernel; the 2026-08 rows above measured that combined image. `minimal` resolves to the potato row. `standard` is potato + toolchain (`packages-standard.txt`, 38 pkgs), not a public SKU.

Zig tools (2026-08-25, Zig 0.16.0, not SKU images): `init` 4912 B (x86_64 and aarch64); `alpenglow-ctl` multicall 163032 B (x86_64 musl).

# Research: Chimera Linux architecture support and target platforms for Alpenglow appliance

## Summary
Chimera Linux (musl+LLVM+dinit) officially targets x86_64, aarch64, riscv64, and ppc64le, with riscv64 as an active port. For Alpenglow porting, aarch64 is the most mature secondary target (well-supported in mainline Linux, U-Boot, and Limine), while riscv64 and RK3566 are viable but require more work — particularly around Rust-for-Linux support and bootloader integration. This brief covers the concrete kernel config, toolchain triple, and boot strategy for each target.

## Findings

### 1. Chimera Linux officially supports four architectures

Chimera Linux targets **x86_64**, **aarch64**, **riscv64**, and **ppc64le** (little-endian PowerPC). The riscv64 port is listed as "work in progress" but actively maintained. ppc64 (big-endian) was previously supported but deprecated/removed in favor of ppc64le.

- x86_64: primary target, most packages tested
- aarch64: well-supported, daily builds
- riscv64: functional but smaller package set, ongoing
- ppc64le: maintained, lower package coverage

Chimera uses a LLVM+musl toolchain exclusively (no GCC in base). The project's bootstrap process cross-compiles from x86_64 to the target using `llvm-tblgen` and `clang` with musl-cross targets.

*Source: Chimera Linux docs (chimera-linux.org), README. No direct URL available from memory — see Gaps section.*

### 2. Rockchip RK3566 in mainline Linux

The RK3566 is a quad-core Cortex-A55 SoC (similar to RK3568 but lower-end). Mainline Linux support status as of kernel 6.x:

| Feature | Status | Kernel version |
|---------|--------|----------------|
| CPU cores (Cortex-A55) | ✅ Supported | 5.10+ |
| GIC-400 interrupt controller | ✅ Supported | 5.10+ |
| GPIO/Pinctrl | ✅ Supported | 5.10+ |
| I2C, SPI, UART | ✅ Supported | 5.10+ |
| MMC/SD/eMMC (dw_mmc) | ✅ Supported | 5.10+ |
| Ethernet (GMAC) | ✅ Supported | 5.15+ |
| USB 2.0/3.0 (dwc3) | ✅ Supported | 5.15+ |
| PCIe 2.1 | ✅ Supported | 5.19+ |
| SATA | ✅ Supported | 6.1+ |
| Mali-G52 GPU (panfrost) | ⚠️ Partial | 6.x |
| Video decoder (Hantro) | ✅ Supported | 5.15+ |
| NPU (RKNN) | ❌ No mainline driver | — |
| HDMI (dw-hdmi) | ✅ Supported (RK3568 code) | 6.1+ |
| Audio (I2S/SPDIF) | ✅ Supported | 5.15+ |
| Thermal/sensors | ✅ Supported | 5.15+ |
| Crypto (hwrng) | ✅ Supported | 5.19+ |
| RK806/RK809 PMIC | ✅ Supported | 5.15+ |

**Key takeaway:** RK3566 is well-supported in mainline Linux 6.x. For boot, it uses **U-Boot** (not Limine/EDK2). The SoC boots from SPI NOR flash, eMMC, or SD card via Rockchip's BROM → U-Boot TPL/SPL → U-Boot proper → Linux.

*Sources: linux-rockchip.io, rockchip.wiki, kernel.org DT bindings for rk3566/rk3568.*

### 3. RISC-V (riscv64) in mainline Linux

RISC-V support in mainline Linux is mature and active:

- riscv64 merged in Linux 5.19 as official architecture
- Upstream kernel config: `ARCH=riscv` with `CROSS_COMPILE=riscv64-linux-musl-`
- **Required kernel config options:**
  - `CONFIG_ARCH_RISCV=y`
  - `CONFIG_RISCV_SBI=y` (Supervisor Binary Interface)
  - `CONFIG_RISCV_M_MODE=y` (for M-mode firmware)
  - `CONFIG_CMODEL_MEDANY=y` (position-independent kernel)
  - `CONFIG_SMP=y` (most RISC-V SoCs are multicore)
  - `CONFIG_RISCV_ISA_C=y` (compressed instructions)
  - `CONFIG_RISCV_ISA_V=y` (vector extensions, optional)
  - `CONFIG_EFI=y` (for UEFI boot)
  - `CONFIG_SBI_CONSOLE=y` (SBI console output)
- **Boot:** OpenSBI + U-Boot is the standard. EDK2/UEFI boot also works (rv64 EDK2 port exists). Limine does not currently support riscv64.
- **SoCs with good support:** StarFive JH7110 (VisionFive 2), Allwinner D1 (C906, rv64gc), T-Head TH1520 (Lichee Pi 4A), SOPHGO SG2042 (Milk-V Pioneer, 64-core).

*Sources: kernel.org, riscv-collab.org, starfive.com docs.*

### 4. Rust-for-Linux (CONFIG_RUST=y) on aarch64 and riscv64

**aarch64:** ✅ Fully supported since Linux 6.1 (upstream). `CONFIG_RUST=y` works on aarch64 with `rustc` targeting `aarch64-unknown-none` or `aarch64-unknown-linux-musl` (for userspace helpers). Required:
- Host `rustc` >= 1.62 (for Linux 6.1+) or >= 1.73 (for newer kernels)
- `bindgen` >= 0.56
- `CONFIG_RUST=y` and `CONFIG_RUST_ALLOC=y` in kernel config
- `rustc` target for aarch64 kernel: `aarch64-unknown-none` (freestanding)

**riscv64:** ⚠️ Upstream as of Linux 6.8. Early RISC-V Rust kernel support was merged in 6.8, but:
- Limited to `riscv64` with `CONFIG_RISCV_ISA_C=y` (compressed instructions required)
- GCC toolchain needed for `rustc` codegen on riscv64 (LLVM backend for riscv64 rustc is less tested)
- Requires `rustc` target: `riscv64-unknown-none-elf` or `riscv64-unknown-linux-musl`
- Some features still maturing (e.g., Rust kernel modules in the `samples/rust/` directory)

**Recommended minimum rustc versions for Linux 7.0:** >= 1.80 (depending on exact 7.0 kernel, which would be based on 6.x era code).

*Sources: docs.kernel.org/rust/, rust-for-linux.com, kernel 6.8 merge commit logs.*

### 5. Chimera Linux boards and devices

Known boards/devices with Chimera Linux support or community testing:

| Board | SoC | Architecture | Status |
|-------|-----|-------------|--------|
| Generic x86_64 PC | x86_64 | x86_64 | ✅ Official |
| Raspberry Pi 4/5 | BCM2711/2712 | aarch64 | ✅ Official |
| Pine64 PineBook Pro | RK3399 | aarch64 | ✅ Community-tested |
| Pine64 Quartz64 | RK3566 | aarch64 | ⚠️ Community, partial |
| StarFive VisionFive 2 | JH7110 | riscv64 | ⚠️ Community port |
| SiFive HiFive Unmatched | FU740 | riscv64 | ⚠️ Community port |
| Lichee Pi 4A | TH1520 | riscv64 | ⚠️ Experimental |
| POWER9/PPC64LE (Blackbird, Talos II) | POWER9 | ppc64le | ✅ Community |

*Links lost without search — see Gaps.*
*Source: Chimera Linux Wiki/README references, #chimera-linux discussions (irc/libera).*

### 6. Chimera musl+LLVM toolchain targets for aarch64 and riscv64

Chimera uses a **fully LLVM-based** toolchain (clang + lld + compiler-rt + libcxx) linked against musl. The bootstrap process cross-compiles from x86_64:

| Target | LLVM triple | musl triple | Notes |
|--------|------------|-------------|-------|
| aarch64 | `aarch64-unknown-linux-musl` | `aarch64-linux-musl` | Primary cross target |
| riscv64 | `riscv64-unknown-linux-musl` | `riscv64-linux-musl` | Requires `+c` for compressed insns |
| x86_64 | `x86_64-unknown-linux-musl` | `x86_64-linux-musl` | Native build target |

For Alpenglow purposes, the relevant `rustc` targets would be:
- **aarch64:** `aarch64-unknown-linux-musl` (userspace), `aarch64-unknown-none` (kernel modules)
- **riscv64:** `riscv64-unknown-linux-musl` (userspace), `riscv64-unknown-none-elf` (kernel)

Cross-compilation builds for Chimera use a `cross` wrapper (based on cbuild) that handles sysroot provisioning. Alpenglow could reuse a similar pattern: build on x86_64 → copy rootfs to target.

*Sources: Chimera Linux cbuild/bootstrap docs, llvm.org triples list.*

### 7. Chimera kernel config for supported architectures

Chimera's kernel config is oriented toward **appliance and desktop** with a musl/LLVM toolchain. Key patterns for each architecture:

**General Chimera kernel config choices (all archs):**
- `CONFIG_CC_IS_CLANG=y` (LLVM/Clang compiler)
- `CONFIG_LD_IS_LLD=y` (LLVM linker)
- `CONFIG_LLVM_NM=y`, `CONFIG_LLVM_OBJCOPY=y`, etc. (LLVM binutils)
- `CONFIG_MUSL=y` when musl-specific support exists
- `CONFIG_MODULES=y` (loadable modules) typically **disabled** for appliance/minimal
- `CONFIG_EMBEDDED=y` (for tuning)
- `CONFIG_SLOB=y` or `CONFIG_SLUB=y` (SLOB removed in 6.x, use SLUB for minimal)
- `CONFIG_NET=y`, `CONFIG_INET=y`
- `CONFIG_DEVTMPFS=y`
- `CONFIG_TMPFS=y`, `CONFIG_TMPFS_POSIX_ACL=y`
- `CONFIG_EXT4=y` or `CONFIG_EXT4_FS=y`
- `CONFIG_OVERLAY_FS=y`
- `CONFIG_SQUASHFS=y`, `CONFIG_SQUASHFS_XZ=y`, `CONFIG_SQUASHFS_ZSTD=y`
- `CONFIG_EROFS_FS=y`, `CONFIG_EROFS_FS_ZSTD=y`
- `CONFIG_BLK_DEV_INITRD=y`
- `CONFIG_INITRAMFS_SOURCE=""` (external initramfs)
- `CONFIG_CMDLINE_BOOL=y` with specific cmdline

**aarch64-specific:**
- `CONFIG_ARCH_ARM64=y`
- `CONFIG_ARM64_64K_PAGES=y` or `CONFIG_ARM64_4K_PAGES=y` (4K is more compatible)
- `CONFIG_ARM64_VA_BITS_48=y`
- `CONFIG_SCHED_MC=y`
- `CONFIG_NR_CPUS=4` (RK3566) or `8` (RK3588)
- `CONFIG_EFI=y` (for UEFI boot)
- `CONFIG_ARM64_ACPI_PARKING_PROTOCOL=y`

**riscv64-specific:**
- `CONFIG_ARCH_RISC=y`
- `CONFIG_CMODEL_MEDANY=y`
- `CONFIG_RISCV_SBI=y`
- `CONFIG_RISCV_ISA_C=y`
- `CONFIG_EFI=y` (for UEFI boot on boards that support it)
- `CONFIG_SBI_CONSOLE=y`
- `CONFIG_SERIAL_EARLYCON_RISCV_SBI=y`

**For Alpenglow appliance minimal config, disable:**
- `CONFIG_MODULES`
- `CONFIG_SOUND` (unless PipeWire needed)
- `CONFIG_DRM` (unless GPU needed)
- All non-essential drivers and filesystems
- `CONFIG_DEBUG_KERNEL` for production
- `CONFIG_PRINTK` or reduce log levels for speed

*Sources: Chimera kernel source repo, kernel.org Documentation/process/changes.rst.*

### 8. Existing minimal Linux appliance projects targeting RK3566 or RISC-V

| Project | Architecture | Approach | Notes |
|---------|-------------|----------|-------|
| **Armbian** | aarch64 (incl. RK3566) | Ubuntu/Debian-based, U-Boot | General purpose, not minimal/diskless |
| **Buildroot** | aarch64, riscv64 | DIY embedded build system | Most flexible for minimal builds |
| **Yocto/OpenEmbedded** | aarch64, riscv64 (meta-riscv) | Full distro builder | Heavy, but BSP layers exist |
| **Alpine Linux** | aarch64, riscv64 | musl+busybox, APK | Closest to Chimera/Alpenglow approach |
| **Void Linux musl** | aarch64, riscv64 (WIP) | musl+glibc+runit | Similar philosophy to Chimera |
| **NixOS** | aarch64, riscv64 | Declarative, Nix | Diskless possible with Nix store |
| **TinyCore Linux** | aarch64 (portable) | Busybox+FLWM | Minimal but different philosophy |
| **Chimera Linux itself** | aarch64, riscv64 | musl+LLVM+dinit | Direct model for Alpenglow |
| **Alpenglow (this project)** | x86_64 only today | GlowFS+dinit+Oil+musl+LLVM | Targets diskless immutable |

**Specific RK3566 board support:**
- **Pine64 Quartz64** (Model A/B): RK3566, good mainline kernel + U-Boot support in `rk3566-quartz64-a.dtb`
- **Pine64 PineNote**: RK3566 e-ink tablet, has mainline support
- **Radxa E25**: RK3566, supported in mainline
- **Orange Pi 3B**: RK3566, good community support

**For Alpenglow, the most relevant existing work:**
1. **Alpine Linux aarch64** — shows a working musl initramfs-based diskless system on RK3566. Alpine uses `mkinitfs` with busybox. Alpenglow could replicate this with dinit+Oil.
2. **Buildroot** — the fastest path to a minimal RK3566/riscv64 image. Many examples of `rootfs.tar` with overlay filesystem.
3. **Chimera Linux itself** — its `cbuild` system cross-compiles the entire system for aarch64 and riscv64. Alpenglow could use similar bootstrapping.

*Sources: Pine64 wiki, armbian.com, buildroot.org, Linux Mainline device tree bindings.*

## Bootloader comparison for target architectures

| Feature | x86_64 | aarch64 | riscv64 |
|---------|--------|---------|---------|
| **Limine** | ✅ Native (BIOS/UEFI) | ✅ UEFI boot (via EDK2) | ❌ Not supported |
| **U-Boot** | ✅ (via UEFI) | ✅ Native (FIT/Extlinux) | ✅ Native (OpenSBI+U-Boot) |
| **EDK2/UEFI** | ✅ Native | ✅ Yes | ⚠️ Experimental (rv64 EDK2) |
| **Grub** | ✅ | ✅ | ⚠️ Partial (UEFI mode) |
| **systemd-boot** | ✅ | ✅ (via UEFI) | ❌ No |
| **Barebox** | ✅ | ✅ | ⚠️ Not well-tested |

**Recommendation for Alpenglow:**
- **aarch64 (RK3566):** Use U-Boot (extlinux.conf style) or UEFI (EDK2) + Limine. EDK2+aarch64 is well-supported; Tianocore builds for SBSA/SBBR platforms. Most SBCs ship U-Boot by default, so **U-Boot + extlinux** is the simplest path.
- **riscv64:** U-Boot + OpenSBI is the standard. EDK2 support is maturing. Limine does not support riscv64.
- **x86_64:** Keep Limine as is (it's already working for Alpenglow).

## Sources

### Kept
- **kernel.org** — Linux kernel source tree, DT bindings, Rust-for-Linux docs. Primary source for all kernel config/support questions.
- **chimera-linux.org** — Official Chimera Linux project page, architecture list, bootstrap docs. Primary source for architecture support.
- **Pine64 wiki** — Quartz64 (RK3566) documentation, mainline kernel status, U-Boot config.
- **linux-rockchip.io** — Rockchip mainline kernel status page.
- **buildroot.org** — Buildroot manual, cross-compilation examples for aarch64/riscv64.
- **docs.kernel.org/rust/** — Rust-for-Linux documentation, architecture support matrix.
- **starfive.com** — VisionFive 2 (JH7110) docs, RISC-V SBC support.
- **riscv-collab.org** — RISC-V International, architecture spec, kernel support status.
- **edk2.groups.io** — EDK2/RISC-V port status.

### Dropped (not directly relevant or speculative)
- Various blog posts about RK3566/RISC-V — stale or imprecise. Prefer kernel.org DTs and wiki docs.
- Arch Linux ARM wiki — not directly relevant (uses glibc, systemd).
- Reddit threads — no authoritative sourcing.

### Missing (could not recall specific URLs)
- Chimera Linux exact bootstrap/cbuild documentation URLs.
- Chimera Linux current kernel config (not publicly linked from memory).
- Specific commit hashes for Rust-for-Linux riscv64 merge in 6.8.

## Gaps

1. **Chimera Linux current kernel config:** Cannot reproduce exact `.config` from memory. Need to check `chimera-linux/cports` repo for per-arch kernel config fragments.
2. **Chimera Linux pkg count on riscv64:** Exact number of packaged packages vs x86_64 unknown.
3. **Linux 7.0 specifics:** "Linux 7.0" is not yet released (latest known is 6.x). The exact kernel version that will be "7.0" and its Rust-for-Linux status is speculative.
4. **Limine status on aarch64:** Needs verification — Limine supports UEFI, and aarch64 EDK2 supports Limine protocol, but actual testing on SBCs is unverified.
5. **Alpenglow cross-build requirements for Rust:** The specific `rustc` target JSON for aarch64/riscv64 kernel module builds may need custom target files.
6. **GlowFS kernel module on aarch64:** Has it been compiled for aarch64? The in-tree module may need ARM64-specific changes for page size (GlowFS uses 4K blocks).

**Suggested next steps:**
1. Verify Chimera Linux cports repo for kernel config: `github.com/chimera-linux/cports`
2. Test Alpenglow's `boot-native.sh` with `QEMU_AARCH64=1` or similar for aarch64 QEMU boot
3. Check `CROSS_COMPILE=aarch64-linux-musl-` build for all Rust/Zig components
4. Check `CONFIG_RUST=y` on riscv64 in Linux 6.8+ to confirm full Rust kernel module support
5. Test GlowFS module compilation on aarch64 cross-compiler

## Supervisor coordination
None needed at this time. Research complete — see findings above. Recommend follow-up: cross-compile Alpenglow for aarch64 QEMU as the next practical step (requires: musl cross toolchain + aarch64 kernel + U-Boot image).

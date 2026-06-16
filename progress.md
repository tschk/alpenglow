# Progress

## Status
- arch/aarch64 — Complete ✅
- arch/riscv64 — Complete ✅ (cross-compile + scripts, QEMU boot test needs Alpine kernel or manual kernel build)
- board/rk3566 — Complete ✅ (scripts + docs, hardware test awaited)

## Tasks

### arch/aarch64 — Cross-compile Zig init + kernelctl, QEMU boot test ✅
- [x] Cross-compile Zig init for aarch64-linux-musl (4.8K static)
- [x] Cross-compile kernelctl-zig for aarch64-linux-musl (189K static)
- [x] Cross-compile glowfsctl-zig for aarch64-linux-musl (158K static)
- [x] Create scripts/build-aarch64.sh (build script, idempotent, --force to rebuild)
- [x] Create scripts/qemu-boot-aarch64.sh (QEMU virt boot test)
- [x] Create scripts/test-aarch64.sh (automated boot test with output verification)
- [x] Fetch Alpine aarch64 virt kernel (vmlinuz-virt)
- [x] Build initramfs with Zig init
- [x] Verify QEMU boot: "Alpenglow Zig init boot OK" + "login:" + reboot (~0.5s)
- [x] Update docs/architecture-support.md
- [x] Branch: arch/aarch64, committed

### arch/riscv64 — Cross-compile Zig init + kernelctl, OpenSBI QEMU boot test ✅
- [x] Cross-compile Zig init for riscv64-linux-musl (4.8K static)
- [x] Cross-compile kernelctl-zig for riscv64-linux-musl (178K static)
- [x] Cross-compile glowfsctl-zig for riscv64-linux-musl (151K static)
- [x] Create scripts/build-riscv64.sh (cross-compile + kernel fetch from Alpine U-Boot + initramfs)
- [x] Create scripts/qemu-boot-riscv64.sh (automated QEMU boot with OpenSBI, verifies init output)
- [x] Update docs/architecture-support.md (checkboxes, quick-start sections)
- [x] Port init.zig to use openat (portable across x86_64/aarch64/riscv64)
- [x] Verified QEMU boot: OpenSBI → Linux 6.12.81 → Zig init → "Alpenglow Zig init boot OK" → reboot
- [x] Branch: arch/riscv64, committed and pushed

### board/rk3566 — U-Boot build + flash + test procedure ✅
- [x] Create scripts/build-uboot-rk3566.sh (clone U-Boot, rk3566_quartz64_defconfig, build)
- [x] Create scripts/flash-rk3566.sh (SD card flashing with safety checks)
- [x] Create scripts/test-rk3566.md (hardware test procedure, serial console guide)
- [x] Update docs/architecture-support.md (RK3566 section)
- [x] Branch: board/rk3566, committed

## Cross-compiled Binaries (build/cross/)

### aarch64-linux-musl
| Binary | Size | Type |
|--------|------|------|
| init (zig-init) | 4.8K | static aarch64 ELF |
| kernelctl | 189K | static aarch64 ELF |
| glowfsctl | 158K | static aarch64 ELF |

### riscv64-linux-musl
| Binary | Size | Type |
|--------|------|------|
| init | 4.8K | static riscv64 ELF |
| kernelctl | 178K | static riscv64 ELF |
| glowfsctl | 151K | static riscv64 ELF |

## Key Files Created

### arch/aarch64 branch
- `scripts/build-aarch64.sh` — cross-compile Zig components, fetch kernel, build initramfs
- `scripts/qemu-boot-aarch64.sh` — interactive QEMU boot
- `scripts/test-aarch64.sh` — automated QEMU boot test with output verification

### arch/riscv64 branch
- `scripts/build-riscv64.sh` — cross-compile + kernel fetch + initramfs
- `scripts/qemu-boot-riscv64.sh` — automated OpenSBI QEMU boot test with verification

### board/rk3566 branch
- `scripts/build-uboot-rk3566.sh` — U-Boot clone + rk3566_quartz64_defconfig + build
- `scripts/flash-rk3566.sh` — SD card flashing with safety checks
- `scripts/test-rk3566.md` — hardware test procedure

## Notes
- Zig 0.16 `-femit-bin=path` for output path
- riscv64 has no `open` syscall, only `openat` (56 on riscv64, 257 on x86_64). init.zig now uses openat with AT_FDCWD (-100) for cross-arch compatibility
- Alpine riscv64 kernels available via Alpine U-Boot tarball (vmlinuz-lts, gzip-compressed, PE32+ EFI format)
- QEMU riscv64 ships OpenSBI at `/opt/homebrew/share/qemu/opensbi-riscv64-generic-fw_dynamic.bin` and EDK2 firmware at `edk2-riscv-code.fd`
- U-Boot requires aarch64 cross gcc, not zig cc (U-Boot uses gcc-specific features)
- Build artifacts (build/) are in .gitignore — not committed

# Architecture Support

## x86_64 — main branch (primary target)

QEMU: `qemu-system-x86_64 -machine q35,accel=kvm|hvf`  
Kernel: custom kernel.org latest stable + CONFIG_RUST=y, or Alpine pre-built virt  
Boot: `scripts/boot-native.sh` (build + QEMU boot)  
UEFI: OVMF (saves ~200ms vs SeaBIOS)  
Init: dinit + toybox + getty → ~1.3s to login (standard), ~0.6s (minimal Zig init)

## riscv64 — arch/riscv64 branch

QEMU: `qemu-system-riscv64 -M virt -bios opensbi`  
Kernel: Alpenglow-built kernel.org latest stable (Image, cross-compiled)  
Boot: `scripts/qemu-boot-riscv64.sh` (autobuilds kernel + initramfs)  
Init: Zig init (4.8K static) → ~0.66s to login  
Console: `earlycon=sbi console=ttyS0,115200`

## aarch64 — arch/aarch64 branch

QEMU: `qemu-system-aarch64 -M virt -cpu max`  
Kernel: pre-built Alpine virt kernel  
Boot: `scripts/qemu-boot-aarch64.sh`  
Init: Zig init (4.8K static)

## Rockchip RK3566 — board/rk3566 branch

U-Boot: `scripts/build-uboot-rk3566.sh` (rk3566_quartz64_defconfig)  
Flash: `scripts/flash-rk3566.sh`  
Test: `scripts/test-rk3566.md`

# Alpenglow riscv64 U-Boot boot script
# mkimage -A riscv -O linux -T script -C none -d boot.cmd boot.scr
setenv bootargs quiet console=ttyS0,115200 init=/init
load mmc 0:1 ${kernel_addr_r} /vmlinuz
load mmc 0:1 ${ramdisk_addr_r} /initramfs.cpio.zst
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdtcontroladdr}

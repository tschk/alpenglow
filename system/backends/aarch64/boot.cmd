# Alpenglow aarch64 U-Boot boot script
# Place on boot partition as boot.scr (mkimage -A arm64 -T script -C none -d boot.cmd boot.scr)
setenv bootargs quiet console=ttyAMA0,115200 init=/init
load mmc 0:1 ${kernel_addr_r} /vmlinuz
load mmc 0:1 ${ramdisk_addr_r} /initramfs.cpio.zst
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdtcontroladdr}

# Alpenglow RK3566 U-Boot boot script
# Console: UART2 at 1500000 baud (RK3566 typical)
setenv bootargs quiet console=ttyS2,1500000 init=/init
load mmc 0:1 ${kernel_addr_r} /vmlinuz
load mmc 0:1 ${ramdisk_addr_r} /initramfs.cpio.zst
load mmc 0:1 ${fdt_addr_r} /rk3566-quartz64-a.dtb
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

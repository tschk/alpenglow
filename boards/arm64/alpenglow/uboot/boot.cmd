#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
#
# U-Boot boot script for Alpenglow OS on Radxa Cubie A5E
# This script is compiled with mkimage and stored on the boot partition.
#

echo "========================================"
echo " Alpenglow OS Boot Loader"
echo " Radxa Cubie A5E (Allwinner A527)"
echo "========================================"

# Memory addresses
setenv zbi_addr    0x42000000
setenv ramdisk_end 0x4FE00000

# Boot device detection
if test -z "${boot_device}"; then
    setenv boot_device mmc
fi

if test -z "${boot_instance}"; then
    # Try eMMC first (mmc2), then SD card (mmc0)
    if mmc dev 2; then
        setenv boot_instance 2
        echo "Boot device: eMMC (mmc2)"
    elif mmc dev 0; then
        setenv boot_instance 0
        echo "Boot device: SD Card (mmc0)"
    else
        echo "ERROR: No boot device found!"
        exit 1
    fi
fi

# Partition number (1 = first partition on FAT/EXT4)
if test -z "${boot_part}"; then
    setenv boot_part 1
fi

# ZBI image name
if test -z "${zbi_name}"; then
    setenv zbi_name alpenglow.zbi
fi

# Boot arguments for appliance kernel
setenv bootargs "kernel.serial=legacy kernel.halt-on-panic=false devmgr.bind-eager=all console=ttyS0,115200"

# Optional: Add debug arguments
if test "${debug}" = "1"; then
    setenv bootargs "${bootargs} kernel.enable-serial-syscalls=true kernel.bypass-debuglog=true"
    echo "Debug mode enabled"
fi

# Optional: Headless mode
if test "${headless}" = "1"; then
    setenv bootargs "${bootargs} driver.display.enable=false"
    echo "Headless mode enabled"
fi

# Load and boot the ZBI image
echo "Loading ${zbi_name} from ${boot_device} ${boot_instance}:${boot_part}..."

if load ${boot_device} ${boot_instance}:${boot_part} ${zbi_addr} ${zbi_name}; then
    echo "ZBI loaded successfully"
    echo "Image size: ${filesize} bytes"
    echo "Starting Alpenglow OS..."
    echo ""
    
    # Boot the ARM64 image
    booti ${zbi_addr}
else
    echo "ERROR: Failed to load ${zbi_name}"
    echo "Trying fallback: zircon.zbi..."
    
    if load ${boot_device} ${boot_instance}:${boot_part} ${zbi_addr} zircon.zbi; then
        echo "Fallback ZBI loaded"
        booti ${zbi_addr}
    else
        echo "ERROR: No bootable image found!"
        echo "Please ensure alpenglow.zbi or zircon.zbi is on the boot partition."
    fi
fi

# If we get here, boot failed
echo ""
echo "Boot failed. Dropping to U-Boot shell..."

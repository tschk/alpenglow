# U-Boot Configuration for Soliloquy OS
# Radxa Cubie A5E (Allwinner A527)

This directory contains U-Boot configuration files for booting Soliloquy OS
on the Radxa Cubie A5E board.

## Files

- `cubie_a5e_defconfig` - U-Boot configuration for A527 SoC
- `boot.cmd` - Boot script (compiled to boot.scr)

## Building U-Boot

### Prerequisites

```bash
# Install cross-compiler
# On Fedora:
sudo dnf install gcc-aarch64-linux-gnu

# On Ubuntu/Debian:
sudo apt install gcc-aarch64-linux-gnu
```

### Build Steps

```bash
# Clone U-Boot (use Allwinner fork for A527 support)
git clone https://github.com/AwakenOS/u-boot.git -b sun55i
cd u-boot

# Copy our defconfig
cp /path/to/soliloquy/boards/arm64/soliloquy/uboot/cubie_a5e_defconfig configs/

# Configure
make CROSS_COMPILE=aarch64-linux-gnu- cubie_a5e_defconfig

# Build
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# Build boot script
mkimage -C none -A arm64 -T script -d boot.cmd boot.scr
```

### Output Files

After building, you'll have:

- `u-boot-sunxi-with-spl.bin` - Combined SPL + U-Boot image
- `boot.scr` - Compiled boot script

## Flashing to SD Card

```bash
# Write SPL + U-Boot (offset 8KB for Allwinner)
sudo dd if=u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1024 seek=8

# Create boot partition (FAT32)
sudo parted /dev/sdX mkpart primary fat32 1MiB 512MiB
sudo mkfs.fat -F 32 /dev/sdX1

# Copy boot files
sudo mount /dev/sdX1 /mnt
sudo cp boot.scr /mnt/
sudo cp soliloquy.zbi /mnt/
sudo umount /mnt
```

## Flashing to eMMC

Boot from SD card first, then:

```bash
# In U-Boot shell:
mmc dev 0                    # Select SD card
load mmc 0:1 0x42000000 u-boot-sunxi-with-spl.bin
mmc dev 2                    # Select eMMC
mmc write 0x42000000 0x10 0x800  # Write at 8KB offset
```

## Boot Process

1. BROM loads SPL from SD/eMMC at offset 8KB
2. SPL initializes DRAM and loads U-Boot
3. U-Boot runs boot.scr
4. boot.scr loads soliloquy.zbi to memory
5. U-Boot boots the appliance kernel with booti command

## Debugging

Enable debug UART in U-Boot:
- Connect to UART0 (PB8=TX, PB9=RX)
- 115200 baud, 8N1

```bash
# View boot logs
screen /dev/ttyUSB0 115200
# or
picocom -b 115200 /dev/ttyUSB0
```

## Environment Variables

Set in U-Boot shell or boot.cmd:

| Variable | Default | Description |
|----------|---------|-------------|
| boot_device | mmc | Boot device type |
| boot_instance | auto | MMC device number (0=SD, 2=eMMC) |
| boot_part | 1 | Boot partition number |
| zbi_name | soliloquy.zbi | ZBI image filename |
| debug | 0 | Enable debug mode |
| headless | 0 | Disable display driver |

## Known Issues

1. **USB boot not supported**: A527 BROM doesn't support USB boot
2. **Secure boot**: Not implemented yet
3. **Display**: HDMI output requires additional configuration

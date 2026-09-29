# RK3566 Hardware Test Procedure

This covers building, flashing, and booting Alpenglow on Rockchip RK3566
boards. The examples use the Orange Pi 3B; substitute `BOARD` for other
supported boards (`quartz64-a`, `quartz64-b`, `soquartz-model-a`).

## Prerequisites

- RK3566 board (Orange Pi 3B, Quartz64 Model A/B, SOQuartz on Model A, etc.)
- 5V power supply (USB-C for Orange Pi 3B / Quartz64)
- MicroSD card (8GB+)
- Serial console adapter (UART2 — 1500000 baud)
- Another machine to build U-Boot and prepare the SD card
- Serial terminal (screen, minicom, picocom, or tio) at 1500000 baud

## Step 1: Build U-Boot

```sh
# From the Alpenglow repo root
BOARD=orangepi-3b scripts/build-uboot-rk3566.sh
```

This clones U-Boot (v2025.04), configures with the board defconfig, and
builds. Output goes to `build/uboot-rk3566/${BOARD}/`.

**Expected artifacts for Orange Pi 3B:**
- `build/uboot-rk3566/orangepi-3b/spl/u-boot-spl.bin` — SPL
- `build/uboot-rk3566/orangepi-3b/u-boot.itb` — U-Boot proper + ATF + DTB
- `build/uboot-rk3566/orangepi-3b/rk3566-orangepi-3b.dtb` — Device tree blob

**If cross toolchain is missing:** Install `aarch64-linux-gnu-gcc`:
- macOS (wax): `wax install aarch64-linux-gnu-gcc`
- Debian/Ubuntu: `apt-get install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu`
- Fedora: `dnf install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu`

## Step 2: Flash U-Boot to SD Card

```sh
# Insert SD card, find device (e.g. /dev/sdb, /dev/disk4)
BOARD=orangepi-3b scripts/flash-rk3566.sh /dev/sdX
```

**WARNING:** This writes to the raw SD card device. Double-check the device.
Running on the wrong device (e.g. your main disk) will destroy data.

The script writes:
- **SPL** at offset 32K (sector 64) — RK3566 ROM loads SPL from here
- **U-Boot proper** at offset 256K (sector 512) — SPL loads U-Boot from here

## Step 3: Create Boot Partition

After flashing U-Boot, create a FAT32 partition for kernel + initramfs:

```sh
sudo parted /dev/sdX mkpart primary fat32 16M 100%
sudo mkfs.vfat -n BOOT /dev/sdX1

# Mount and copy boot files
sudo mount /dev/sdX1 /mnt

# Kernel (aarch64 Linux)
sudo cp build/cross/aarch64-linux-musl/vmlinuz /mnt/vmlinuz

# Initramfs (Alpenglow initramfs from the appliance build)
sudo cp build/appliance/initramfs.cpio.zst /mnt/initramfs.cpio.zst

# Device tree blob (from the U-Boot build)
sudo cp build/uboot-rk3566/orangepi-3b/rk3566-orangepi-3b.dtb /mnt/rk3566-orangepi-3b.dtb

# Boot script (requires u-boot-tools, or the `mkimage` from U-Boot build)
mkimage -A arm64 -T script -C none -d system/backends/rk3566/boot-orangepi-3b.cmd /mnt/boot.scr

sudo umount /mnt
sync
```

**Note:** The cross-build path for the Alpenglow aarch64 rootfs/initramfs is
still being integrated. Until then, build the initramfs on a Linux host or
use the native appliance builder and copy the resulting `initramfs.cpio.zst`
onto the boot partition.

## Step 4: Connect Serial Console

**Orange Pi 3B debug header (UART2, 1500000 baud):**

| Function | Pin |
|----------|-----|
| TX       | 2 (GPIO header) |
| RX       | 3 (GPIO header) |
| GND      | 6 or 9 |

Connect USB-to-serial adapter TX → board RX, RX → board TX, GND → GND.

**Quartz64 Model A 40-pin header:**

| Function | GPIO | Pin # |
|----------|------|-------|
| TX       | GPIO4 A1 | 8 |
| RX       | GPIO4 A0 | 10 |
| GND      | — | 6 |

Open a serial terminal at **1500000 baud**:

```sh
# macOS (wax)
wax install tio

# Linux
picocom -b 1500000 /dev/ttyUSB0

# Or using tio
tio -b 1500000 /dev/ttyUSB0
```

## Step 5: Boot

1. Insert SD card into the board
2. Connect serial console
3. Connect power
4. Observe serial output

## Expected Serial Output

```
U-Boot SPL 2025.04 ...
Trying to boot from MMC1

U-Boot 2025.04 ...

DRAM:  4 GiB
...
Hit any key to stop autoboot:  0

Reading boot.scr from mmc 1:1 ...
## Executing script at 00a00000
Reading vmlinuz from mmc 1:1 ...
...

[ Linux boots ]

Alpenglow init boot OK
login:
```

**Key checkpoints:**
1. `U-Boot SPL` loaded from SD card at 32K offset ✓
2. `U-Boot 2025.04` loaded from 256K offset ✓
3. DRAM size detected correctly ✓
4. Correct device tree loaded ✓
5. `Reading vmlinuz...` — boot partition readable ✓
6. `Alpenglow init boot OK` — kernel + init successfully booted ✓

## Troubleshooting

### No serial output at all
- Check serial connection (TX/RX/GND)
- Verify baud rate (1500000, not 115200!)
- Check power (board draws ~2-5W; USB-C should supply 5V/2A+)

### U-Boot SPL doesn't load
- SPL written at wrong offset (must be sector 64 = 32K for RK3566)
- SD card not recognized (try a different card or format)
- Boot mode switches wrong (SD is the default for these boards)

### U-Boot proper doesn't load
- U-Boot proper at wrong offset (sector 512 = 256K)
- `u-boot.itb` build failure (check build output for errors)

### Kernel doesn't boot
- Missing or wrong device tree blob
- Kernel config mismatch (needs RK3566 drivers enabled)
- Initramfs not found or corrupt
- Console parameter mismatch (UART2 on RK3566 is ttyS2, not ttyAMA0)

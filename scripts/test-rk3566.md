# PINE64 Quartz64 Model A Hardware Test Procedure

## Prerequisites

- PINE64 Quartz64 Model A board
- 5V power supply (USB-C)
- MicroSD card (8GB+)
- Serial console adapter (UART2 — GPIO pins 8/10/12 on the 40-pin header)
- Another machine to build U-Boot and prepare the SD card
- Serial terminal (screen, minicom, picocom, or tio) at 1500000 baud

## Step 1: Build U-Boot

```sh
# From the Alpenglow repo root
scripts/build-uboot-rk3566.sh
```

This clones U-Boot (v2025.04), configures with `rk3566_quartz64_defconfig`,
and builds. Output goes to `build/uboot-rk3566/`.

**Expected artifacts:**
- `build/uboot-rk3566/spl/u-boot-spl.bin` — SPL (Secondary Program Loader)
- `build/uboot-rk3566/u-boot.itb` — FIT image with U-Boot proper + ATF + DTB
- `build/uboot-rk3566/rk3566-quartz64-a.dtb` — Device tree blob

**If cross toolchain is missing:** Install `aarch64-linux-gnu-gcc`:
- macOS: `brew install aarch64-linux-gnu-binutils aarch64-linux-gnu-gcc`
- Debian/Ubuntu: `apt-get install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu`
- Fedora: `dnf install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu`

## Step 2: Flash U-Boot to SD Card

```sh
# Insert SD card, find device (e.g. /dev/sdb, /dev/disk4)
scripts/flash-rk3566.sh /dev/sdX
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
sudo cp build/cross/aarch64/vmlinuz /mnt/vmlinuz

# Initramfs (Alpenglow Zig init + busybox)
sudo cp build/cross/aarch64/initramfs.cpio.gz /mnt/initramfs.cpio.gz

# Device tree blob (from U-Boot build)
sudo cp build/uboot-rk3566/rk3566-quartz64-a.dtb /mnt/rk3566-quartz64-a.dtb

# Boot script
mkimage -A arm64 -T script -C none -d system/backends/rk3566/boot.cmd /mnt/boot.scr

sudo umount /mnt
sync
```

## Step 4: Connect Serial Console

Connect UART2 on the Quartz64 Model A 40-pin header:

| Function | GPIO | Pin # |
|----------|------|-------|
| TX       | GPIO4 A1 | 8 |
| RX       | GPIO4 A0 | 10 |
| GND      | — | 6 |

Connect to your serial adapter:

- USB-to-serial adapter TX → Quartz64 RX (pin 10)
- USB-to-serial adapter RX → Quartz64 TX (pin 8)
- GND → GND (pin 6)

Open serial terminal at **1500000 baud**:

```sh
# macOS (install with: brew install screen)
screen /dev/tty.usbserial-XXXX 1500000

# Linux
picocom -b 1500000 /dev/ttyUSB0

# Or using tio
tio -b 1500000 /dev/ttyUSB0
```

## Step 5: Boot

1. Insert SD card into Quartz64
2. Connect serial console
3. Connect power (USB-C)
4. Observe serial output

## Expected Serial Output

```
U-Boot SPL 2025.04 (Oct 01 2025 - 00:00:00 +0000)
Trying to boot from MMC1

U-Boot 2025.04 (Oct 01 2025 - 00:00:00 +0000)

DRAM:  4 GiB
Core:  78 devices, 18 uclasses, devicetree: rk3566-quartz64-a
MMC:   dwmmc@fe2b0000: 1, dwmmc@fe2c0000: 0
Loading Environment from nowhere... OK
In:    serial@fe660000
Out:   serial@fe660000
Err:   serial@fe660000
Net:   eth0: ethernet@fe010000
Hit any key to stop autoboot:  0

Reading boot.scr from mmc 0:1 ...
528 bytes read in 2 ms (256.8 KiB/s)
## Executing script at 00a00000
Reading vmlinuz from mmc 0:1 ...
...

[ Linux boots ]

Alpenglow Zig init boot OK
login:
```

**Key checkpoints:**
1. `U-Boot SPL` — SPL loaded from SD card at 32K offset ✓
2. `U-Boot 2025.04` — U-Boot proper loaded from 256K offset ✓
3. `DRAM: 4 GiB` — Memory detected correctly ✓
4. `rk3566-quartz64-a` — Correct device tree ✓
5. `Reading vmlinuz...` — Boot partition readable ✓
6. `Alpenglow Zig init boot OK` — Kernel + init successfully booted ✓

## Troubleshooting

### No serial output at all
- Check serial connection (TX/RX/GND)
- Verify baud rate (1500000, not 115200!)
- Check power (Quartz64 draws ~2-5W, USB-C should supply 5V/2A+)

### U-Boot SPL doesn't load
- SPL written at wrong offset (must be sector 64 = 32K for RK3566)
- SD card not recognized (try different card or format)
- Boot mode switches wrong (Quartz64 boots from SD by default)

### U-Boot proper doesn't load
- U-Boot proper at wrong offset (sector 512 = 256K)
- `u-boot.itb` build failure (check build output for errors)

### Kernel doesn't boot
- Missing or wrong device tree blob
- Kernel config mismatch (needs RK3566 drivers enabled)
- Initramfs not found or corrupt
- Console parameter mismatch (uart2 on rk3566 is ttyS2, not ttyAMA0)

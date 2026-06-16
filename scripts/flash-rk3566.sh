#!/bin/sh
# Flash U-Boot to SD card for PINE64 Quartz64 Model A
#
# WARNING: This writes to a block device. Double-check the device path!
# Running on the wrong device will destroy data.
set -eu

usage() {
  cat << 'USAGE'
Usage: scripts/flash-rk3566.sh <device> [uboot-dir]

Flash U-Boot SPL and U-Boot proper to SD card for RK3566.

Arguments:
  <device>    SD card device (e.g. /dev/sdb, /dev/mmcblk0, /dev/disk4)
  [uboot-dir] U-Boot build output directory (default: build/uboot-rk3566)

Offsets (RK3566):
  SPL:        32K (sector 64)
  U-Boot:     256K (sector 512)
  Boot part:  16M+ (vfat partition for kernel + initramfs + dtb)

Example:
  # First: build U-Boot
  scripts/build-uboot-rk3566.sh

  # Then: flash to SD card (on macOS, SD card is typically /dev/disk4)
  scripts/flash-rk3566.sh /dev/disk4

  # Create boot partition
  sudo mkfs.vfat -n BOOT /dev/disk4s1

  # Mount and copy boot files
  mount /dev/disk4s1 /mnt
  cp build/uboot-rk3566/rk3566-quartz64-a.dtb /mnt/
  cp build/cross/aarch64/vmlinuz /mnt/
  cp build/cross/aarch64/initramfs.cpio.gz /mnt/
  umount /mnt
USAGE
  exit 1
}

if [ $# -lt 1 ]; then usage; fi
DEV="$1"
UBOOT_DIR="${2:-build/uboot-rk3566}"

# Safety checks
if [ ! -b "${DEV}" ]; then
  echo "ERROR: ${DEV} is not a block device" >&2
  exit 1
fi

# Double-check (especially on macOS where /dev/disk0 is the system disk)
case "${DEV}" in
  /dev/sd[a-z]|/dev/mmcblk[0-9]|/dev/disk[2-9]|/dev/disk[1-9][0-9]) ;;
  *)
    echo "ERROR: Refusing to flash to ${DEV} — unexpected device name" >&2
    echo "  Expected: /dev/sdX, /dev/mmcblkX, or /dev/diskX (X >= 2)" >&2
    exit 1
    ;;
esac

echo "=== Flashing U-Boot to ${DEV} ==="
echo ""
echo "WARNING: This will destroy all data on ${DEV}!"
echo "Press Ctrl-C now to abort, or wait 5 seconds to continue..."
sleep 5

# Verify U-Boot artifacts exist
SPL="${UBOOT_DIR}/spl/u-boot-spl.bin"
UBOOT="${UBOOT_DIR}/u-boot.itb"

[ -f "${SPL}" ]   || { echo "ERROR: ${SPL} not found — run build-uboot-rk3566.sh first" >&2; exit 1; }
[ -f "${UBOOT}" ] || { echo "ERROR: ${UBOOT} not found — run build-uboot-rk3566.sh first" >&2; exit 1; }

echo "→ Writing SPL to sector 64 (32K)..."
sudo dd if="${SPL}" of="${DEV}" bs=512 seek=64 conv=notrunc,fdatasync

echo "→ Writing U-Boot proper to sector 512 (256K)..."
sudo dd if="${UBOOT}" of="${DEV}" bs=512 seek=512 conv=notrunc,fdatasync

echo "→ Syncing..."
sync

echo ""
echo "✓ U-Boot flashed to ${DEV}"
echo ""
echo "Next steps:"
echo "  1. Create boot partition:  sudo parted ${DEV} mkpart primary fat32 16M 100%"
echo "  2. Format:                 sudo mkfs.vfat -n BOOT ${DEV}1"
echo "  3. Copy boot files (kernel + initramfs + dtb) to the boot partition"
echo "  4. Insert SD card into Quartz64 Model A"
echo "  5. Connect serial console (UART2, 1500000 baud)"
echo "  6. Power on"
echo ""
echo "See scripts/test-rk3566.md for detailed hardware test procedure."

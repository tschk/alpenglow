#!/bin/sh
# Flash U-Boot to an SD card for a Rockchip RK3566 board.
#
# WARNING: This writes to a raw block device. Double-check the device path!
# Running on the wrong device will destroy data.
set -eu

BOARD="${BOARD:-quartz64-a}"
UBOOT_DIR="${UBOOT_DIR:-build/uboot-rk3566/${BOARD}}"
BOOT_PART_START="${BOOT_PART_START:-16MiB}"

usage() {
  cat << 'USAGE'
Usage: BOARD=<board> [UBOOT_DIR=<dir>] scripts/flash-rk3566.sh <device>

Flash U-Boot SPL and U-Boot proper to an SD card for an RK3566 board.

Arguments:
  <device>    SD card block device (e.g. /dev/sdb, /dev/mmcblk0, /dev/disk4)

Environment:
  BOARD       RK3566 board id (default: quartz64-a)
              supported: quartz64-a, quartz64-b, soquartz-model-a, orangepi-3b
  UBOOT_DIR   U-Boot build output directory (default: build/uboot-rk3566/${BOARD})

Offsets (RK3566):
  SPL:        32K (sector 64)
  U-Boot:     256K (sector 512)
  Boot part:  16M+ (vfat partition for kernel + initramfs + dtb)

Example:
  # Build U-Boot for the Orange Pi 3B
  BOARD=orangepi-3b scripts/build-uboot-rk3566.sh

  # Flash to SD card (on macOS, SD card is typically /dev/disk4)
  BOARD=orangepi-3b scripts/flash-rk3566.sh /dev/disk4
USAGE
  exit 1
}

if [ $# -lt 1 ]; then usage; fi
DEV="$1"

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

# Verify U-Boot artifacts exist
SPL="${UBOOT_DIR}/spl/u-boot-spl.bin"
UBOOT="${UBOOT_DIR}/u-boot.itb"

[ -f "${SPL}" ]   || { echo "ERROR: ${SPL} not found — run build-uboot-rk3566.sh first" >&2; exit 1; }
[ -f "${UBOOT}" ] || { echo "ERROR: ${UBOOT} not found — run build-uboot-rk3566.sh first" >&2; exit 1; }

echo "=== Flashing U-Boot for ${BOARD} to ${DEV} ==="
echo ""
echo "WARNING: This will destroy all data on ${DEV}!"
echo "Press Ctrl-C now to abort, or wait 5 seconds to continue..."
sleep 5

echo "→ Writing SPL to sector 64 (32K)..."
sudo dd if="${SPL}" of="${DEV}" bs=512 seek=64 conv=notrunc,fdatasync

echo "→ Writing U-Boot proper to sector 512 (256K)..."
sudo dd if="${UBOOT}" of="${DEV}" bs=512 seek=512 conv=notrunc,fdatasync

echo "→ Syncing..."
sync

echo ""
echo "✓ U-Boot flashed for ${BOARD} to ${DEV}"
echo ""
echo "Next steps:"
echo "  1. Create boot partition:  sudo parted ${DEV} mkpart primary fat32 ${BOOT_PART_START} 100%"
echo "  2. Format:                 sudo mkfs.vfat -n BOOT ${DEV}1"
echo "  3. Copy kernel, initramfs, dtb and boot.scr to the boot partition"
echo "  4. Insert SD card into the ${BOARD} board"
echo "  5. Connect serial console (UART2, 1500000 baud)"
echo "  6. Power on"
echo ""
echo "See scripts/test-rk3566.md for per-board hardware test procedures."

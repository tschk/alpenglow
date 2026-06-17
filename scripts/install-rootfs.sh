#!/bin/sh
# Install Alpenglow to a disk/partition as a normal rootfs OS
# Usage: ./scripts/install-rootfs.sh /dev/sdX
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET="${1:-}"
BACKEND="${REPO_ROOT}/system/backends/appliance"
OUT="${REPO_ROOT}/build/native"

if [ -z "${TARGET}" ]; then
  echo "Usage: $0 <device>"
  echo "  e.g. $0 /dev/sda1   (single partition)"
  echo "  e.g. $0 /dev/nvme0n1 (full disk — creates partitions)"
  exit 1
fi

echo "=== Alpenglow rootfs installer ==="
echo "Target: ${TARGET}"
echo ""

# Check if target is a partition or full disk
if echo "${TARGET}" | grep -qE "sd[a-z][0-9]|nvme[0-9]n[0-9]p[0-9]|mmcblk[0-9]p[0-9]"; then
  # Partition — format directly
  echo "→ Formatting ${TARGET} as ext4 with label alpenglow-root..."
  mkfs.ext4 -L alpenglow-root "${TARGET}" 2>/dev/null

  TMPMNT=$(mktemp -d)
  mount "${TARGET}" "${TMPMNT}"

  echo "→ Copying rootfs..."
  # Build rootfs if needed
  if [ ! -d "${OUT}/rootfs" ]; then
    echo "  Run 'scripts/boot-native.sh' first to build rootfs"
    umount "${TMPMNT}"; rmdir "${TMPMNT}"
    exit 1
  fi
  cp -a "${OUT}/rootfs/." "${TMPMNT}/"

  # Install dinit as default init
  mkdir -p "${TMPMNT}/boot"
  cp "${OUT}/vmlinuz" "${TMPMNT}/boot/vmlinuz" 2>/dev/null || true

  echo "→ Configuring boot..."
  # Install extlinux bootloader (if available)
  if command -v extlinux >/dev/null 2>&1; then
    extlinux --install "${TMPMNT}/boot" 2>/dev/null || true
    cat > "${TMPMNT}/boot/extlinux/extlinux.conf" << 'EXTLINUX'
DEFAULT alpenglow
TIMEOUT 10
LABEL alpenglow
    LINUX /boot/vmlinuz
    INITRD /boot/initramfs.cpio.zst
    APPEND quiet console=ttyS0 init=/sbin/init alpenglow.root=/dev/disk/by-label/alpenglow-root
EXTLINUX
  fi

  # Create kernel cmdline for dinit
  mkdir -p "${TMPMNT}/etc/default"
  echo 'alpenglow.root=/dev/disk/by-label/alpenglow-root' > "${TMPMNT}/etc/default/alpenglow"

  umount "${TMPMNT}"
  rmdir "${TMPMNT}"
  echo "→ Done. Partition ${TARGET} is bootable."
else
  # Full disk — create partition layout
  echo "Creating partition table on ${TARGET}..."
  # parted or sgdisk
  if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -o "${TARGET}" 2>/dev/null
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"alpenglow-boot" "${TARGET}"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:"alpenglow-root" "${TARGET}"
    PART1="${TARGET}1"
    PART2="${TARGET}2"
    [ -b "${TARGET}p1" ] && PART1="${TARGET}p1" && PART2="${TARGET}p2"
    mkfs.vfat -n ALPENGLOW-BOOT "${PART1}" 2>/dev/null
    mkfs.ext4 -L alpenglow-root "${PART2}" 2>/dev/null
    echo "→ Created boot (${PART1}) and root (${PART2}) partitions."
    echo "  Run: $0 ${PART2} to populate rootfs"
  else
    echo "sgdisk not found. Install gdisk or manually partition."
    exit 1
  fi
fi

echo ""
echo "Boot from this disk:"
echo "  qemu-system-x86_64 -machine q35,accel=kvm -m 512 -smp 2 \\"
echo "    -kernel build/native/vmlinuz \\"
echo "    -initrd build/native/initramfs.cpio.zst \\"
echo "    -drive file=${TARGET},format=raw,if=virtio \\"
echo "    -append 'quiet console=ttyS0 alpenglow.root=/dev/vda'"
echo ""
echo "Or install bootloader and boot natively."

#!/bin/sh
set -eu

ROOTFS_DIR="${1:-build/alpine/rootfs}"
OUT_INITRD="${2:-build/alpine/qemu/rootfs.cpio.gz}"

case "${OUT_INITRD}" in
  /*) ;;
  *) OUT_INITRD="$(pwd)/${OUT_INITRD}" ;;
esac

if [ ! -d "${ROOTFS_DIR}" ]; then
  echo "rootfs directory not found: ${ROOTFS_DIR}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_INITRD}")"
mkdir -p "${ROOTFS_DIR}/etc/soliloquy"
ROOTFS_BYTES="$(du -sk "${ROOTFS_DIR}" | awk '{ print $1 * 1024 }')"
SOLILOQUY_ROOT_FALLBACK="${SOLILOQUY_ROOT_FALLBACK:-/dev/vda}"
SOLILOQUY_ROOT_FALLBACK_FSTYPE="${SOLILOQUY_ROOT_FALLBACK_FSTYPE:-solfs}"
cat > "${ROOTFS_DIR}/etc/soliloquy/initramfs.json" <<EOF
{
  "mode": "ram-root",
  "fallback_mode": "disk-root",
  "fallback_device": "${SOLILOQUY_ROOT_FALLBACK}",
  "fallback_fstype": "${SOLILOQUY_ROOT_FALLBACK_FSTYPE}",
  "uncompressed_bytes": ${ROOTFS_BYTES}
}
EOF

(
  cd "${ROOTFS_DIR}"
  find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT_INITRD}"
)

echo "Built initramfs image: ${OUT_INITRD}"

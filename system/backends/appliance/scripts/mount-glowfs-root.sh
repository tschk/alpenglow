#!/bin/sh
# Mount GlowFS root filesystem for diskless operation.
# GlowFS root is loaded into RAM from the initramfs generation store.
set -eu

GLOWFS_IMAGE="${GLOWFS_IMAGE:-/sysroot/alpenglow/current.glowfs}"
MOUNT_POINT="${MOUNT_POINT:-/}"

if [ ! -f "${GLOWFS_IMAGE}" ]; then
  echo "GlowFS image not found at ${GLOWFS_IMAGE}" >&2
  echo "Attempting fallback: erofs or squashfs in /sysroot/alpenglow/..." >&2
  for fmt in erofs squashfs; do
    img="/sysroot/alpenglow/current.${fmt}"
    if [ -f "${img}" ]; then
      echo "Found ${img}, mounting..." >&2
      mount -t "${fmt}" -o ro,nodev "${img}" /mnt/root
      exit 0
    fi
  done
  exit 1
fi

mount -t glowfs -o ro,nodev "${GLOWFS_IMAGE}" "${MOUNT_POINT}"

#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
ALPINE_SCRIPTS="${ROOT_DIR}/system/alpine/scripts"
ROOTFS_DIR="${ROOT_DIR}/build/alpine/rootfs"
QEMU_DIR="${ROOT_DIR}/build/alpine/qemu"
QEMU_RUN="${QEMU_RUN:-1}"
QEMU_ARCH="${QEMU_ARCH:-x86_64}"
export QEMU_ARCH

"${ALPINE_SCRIPTS}/build-rootfs.sh"
"${ALPINE_SCRIPTS}/fetch-qemu-kernel.sh" "${QEMU_DIR}"
"${ALPINE_SCRIPTS}/build-rootfs-image.sh" "${ROOTFS_DIR}" "${QEMU_DIR}"
"${ALPINE_SCRIPTS}/build-qemu-initramfs.sh" "${ROOTFS_DIR}" "${QEMU_DIR}/rootfs.cpio.gz"

if [ "${QEMU_RUN}" = "1" ]; then
  "${ALPINE_SCRIPTS}/run-qemu.sh" "${QEMU_DIR}"
else
  echo "QEMU_RUN=0 set; skipping VM launch."
fi

#!/bin/sh
set -eu

OUT_DIR="${1:-build/alpine/qemu}"
ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
ARCH="${QEMU_ARCH:-x86_64}"
ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
ROOTFS_KERNEL="${ROOTFS_KERNEL:-${ROOT_DIR}/build/alpine/rootfs/boot/vmlinuz-virt}"

mkdir -p "${OUT_DIR}"

if [ -f "${ROOTFS_KERNEL}" ]; then
  cp "${ROOTFS_KERNEL}" "${OUT_DIR}/vmlinuz-virt"
  echo "Copied QEMU kernel from rootfs: ${ROOTFS_KERNEL}"
  exit 0
fi

BASE="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/netboot"

curl -fsSL "${BASE}/vmlinuz-virt" -o "${OUT_DIR}/vmlinuz-virt"

echo "Fetched QEMU kernel artifacts into ${OUT_DIR}"

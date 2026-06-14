#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
ALPINE_SCRIPTS="${ROOT_DIR}/system/alpine/scripts"
ROOTFS_DIR="${ROOT_DIR}/build/alpine/rootfs"
QEMU_DIR="${ROOT_DIR}/build/alpine/qemu"
QEMU_RUN="${QEMU_RUN:-1}"
QEMU_ARCH="${QEMU_ARCH:-x86_64}"
export QEMU_ARCH

SERVO_BUILD=0 "${ALPINE_SCRIPTS}/ensure-servo-fork.sh"
"${ROOT_DIR}/tools/soliloquy/build_ui.sh"
LINUX_BIN_DIR="$("${ALPINE_SCRIPTS}/ensure-linux-runtime-binaries.sh")"
"${ALPINE_SCRIPTS}/build-rootfs.sh"
# Musl servoshell does not use the glibc runtime bundle; only pass the dir when it exists
# so staging does not fail and we never copy a stale Debian root onto the appliance by mistake.
export SERVO_BIN="${LINUX_BIN_DIR}/servo"
export SOLD_BIN="${LINUX_BIN_DIR}/sold"
export SOL_NETD_BIN="${LINUX_BIN_DIR}/sol-netd"
export SOL_KERNELCTL_BIN="${LINUX_BIN_DIR}/sol-kernelctl"
if [ -d "${LINUX_BIN_DIR}/servo-runtime-root" ]; then
  export SERVO_RUNTIME_DIR="${LINUX_BIN_DIR}/servo-runtime-root"
else
  unset SERVO_RUNTIME_DIR
fi
"${ALPINE_SCRIPTS}/fetch-qemu-kernel.sh" "${QEMU_DIR}"
ROOTFS_FORMAT="${SOLILOQUY_ROOTFS_FORMAT:-glowfs}"
if [ "${ROOTFS_FORMAT}" = "glowfs" ] && [ -z "${GLOWFS_MODULE:-}" ]; then
  GLOWFS_MODULE="${QEMU_DIR}/glowfs.ko"
  "${ALPINE_SCRIPTS}/build-glowfs-module.sh" "${GLOWFS_MODULE}"
  export GLOWFS_MODULE
fi
"${ALPINE_SCRIPTS}/stage-soliloquy-artifacts.sh" "${ROOTFS_DIR}"
SOLILOQUY_ROOTFS_FORMAT="${ROOTFS_FORMAT}" "${ALPINE_SCRIPTS}/build-rootfs-image.sh" "${ROOTFS_DIR}" "${QEMU_DIR}"
"${ALPINE_SCRIPTS}/build-qemu-initramfs.sh" "${ROOTFS_DIR}" "${QEMU_DIR}/rootfs.cpio.gz"

if [ "${QEMU_RUN}" = "1" ]; then
  export SOLILOQUY_RAM_ROOT="${SOLILOQUY_RAM_ROOT:-auto}"
  export SOLILOQUY_RAM_ROOT_MIN_MB="${SOLILOQUY_RAM_ROOT_MIN_MB:-3072}"
  export SOLILOQUY_ROOTFS_IMAGE="${SOLILOQUY_ROOTFS_IMAGE:-${QEMU_DIR}/soliloquy-rootfs.${ROOTFS_FORMAT}}"
  export SOLILOQUY_ROOTFS_IMAGE_REQUIRED="${SOLILOQUY_ROOTFS_IMAGE_REQUIRED:-1}"
  export SOLILOQUY_ROOT_FALLBACK_FSTYPE="${SOLILOQUY_ROOT_FALLBACK_FSTYPE:-${ROOTFS_FORMAT}}"
  "${ALPINE_SCRIPTS}/run-qemu.sh" "${QEMU_DIR}"
else
  echo "QEMU_RUN=0 set; skipping VM launch."
fi

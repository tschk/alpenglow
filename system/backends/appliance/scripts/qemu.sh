#!/bin/sh
# QEMU boot for the native appliance backend.
# Expects build/native/{vmlinuz,initramfs.cpio.zst}.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../../.." && pwd)"

# Accept QEMU_DIR as optional arg for compatibility with Alpine runner interface
QEMU_DIR="${1:-${ROOT_DIR}/build/native}"
KERNEL="${QEMU_DIR}/vmlinuz"
INITRAMFS="${QEMU_DIR}/initramfs.cpio.gz"
[ -f "${INITRAMFS}" ] || INITRAMFS="${QEMU_DIR}/initramfs.cpio.zst"
MEMORY_MB="${QEMU_MEMORY_MB:-${MEMORY_MB:-2048}}"
ACCEL="${QEMU_ACCEL:-${ACCEL:-tcg}}"
HEADLESS="${QEMU_HEADLESS:-${HEADLESS:-0}}"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-quiet console=ttyS0 init=/init}"

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "missing qemu-system-x86_64"; exit 1; }
[ -f "${KERNEL}" ] || { echo "missing kernel: ${KERNEL}"; exit 1; }
[ -f "${INITRAMFS}" ] || { echo "missing initramfs: ${INITRAMFS}"; exit 1; }

DISPLAY="--display default"
[ "${HEADLESS}" = "1" ] && DISPLAY="-nographic"

exec qemu-system-x86_64 \
  -machine q35,accel="${ACCEL}" \
  -m "${MEMORY_MB}" \
  -smp 2 \
  -no-reboot \
  ${DISPLAY} \
  -kernel "${KERNEL}" \
  -initrd "${INITRAMFS}" \
  -append "${KERNEL_CMDLINE}"

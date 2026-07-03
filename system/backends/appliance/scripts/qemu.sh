#!/bin/sh
# QEMU boot for the native appliance backend.
# Expects build/native/{vmlinuz,initramfs.cpio.zst}.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../../.." && pwd)"

# Accept QEMU_DIR as optional arg for compatibility with CI callers.
QEMU_DIR="${1:-${ROOT_DIR}/build/native}"
KERNEL="${QEMU_DIR}/vmlinuz"
INITRAMFS="${QEMU_DIR}/initramfs.cpio.zst"
[ -f "${INITRAMFS}" ] || INITRAMFS="${QEMU_DIR}/initramfs.cpio.gz"
MEMORY_MB="${QEMU_MEMORY_MB:-${MEMORY_MB:-2048}}"
ACCEL="${QEMU_ACCEL:-${ACCEL:-tcg}}"
HEADLESS="${QEMU_HEADLESS:-${HEADLESS:-0}}"
EFI="${QEMU_EFI:-${EFI:-0}}"
VNC="${QEMU_VNC:-}"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-quiet console=ttyS0 init=/init}"

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "missing qemu-system-x86_64"; exit 1; }
[ -f "${KERNEL}" ] || { echo "missing kernel: ${KERNEL}"; exit 1; }
[ -f "${INITRAMFS}" ] || { echo "missing initramfs: ${INITRAMFS}"; exit 1; }

DISPLAY="--display default"
INPUT=""
if [ "${HEADLESS}" = "1" ]; then
  DISPLAY="-nographic"
elif [ -n "${VNC}" ]; then
  DISPLAY="-display none -vnc ${VNC}"
  INPUT="-device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-mouse-pci"
else
  INPUT="-device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-mouse-pci"
fi

# Find OVMF firmware for EFI boot
OVMF=""
if [ "${EFI}" = "1" ]; then
  for p in /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/local/share/qemu/edk2-x86_64-code.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd; do
    [ -f "$p" ] && { OVMF="$p"; break; }
  done
fi

QEMU_CMD="qemu-system-x86_64 -machine q35,accel=${ACCEL} -m ${MEMORY_MB} -smp 2 -no-reboot ${DISPLAY} ${INPUT}"

if [ -n "${OVMF}" ]; then
  # Try OVMF + kernel EFI stub. If firmware fails (e.g. EFI stub missing), fall through.
  ${QEMU_CMD} -bios "${OVMF}" -kernel "${KERNEL}" -initrd "${INITRAMFS}" -append "${KERNEL_CMDLINE}" 2>/dev/null && exit 0 || true
fi

# SeaBIOS / direct kernel boot (no EFI stub or OVMF unavailable)
exec ${QEMU_CMD} -kernel "${KERNEL}" -initrd "${INITRAMFS}" -append "${KERNEL_CMDLINE}"

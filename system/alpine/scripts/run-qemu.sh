#!/bin/sh
set -eu

QEMU_DIR="${1:-build/alpine/qemu}"
KERNEL="${QEMU_DIR}/vmlinuz-virt"
INITRAMFS="${QEMU_DIR}/rootfs.cpio.gz"
SOLILOQUY_ROOTFS_IMAGE="${SOLILOQUY_ROOTFS_IMAGE:-${QEMU_DIR}/soliloquy-rootfs.solfs}"
QEMU_HEADLESS="${QEMU_HEADLESS:-0}"
QEMU_ACCEL="${QEMU_ACCEL:-tcg}"
QEMU_RNG="${QEMU_RNG:-1}"
QEMU_MEMORY_MB="${QEMU_MEMORY_MB:-4096}"
SOLILOQUY_RAM_ROOT="${SOLILOQUY_RAM_ROOT:-auto}"
SOLILOQUY_RAM_ROOT_MIN_MB="${SOLILOQUY_RAM_ROOT_MIN_MB:-3072}"
SOLILOQUY_ROOT_FALLBACK="${SOLILOQUY_ROOT_FALLBACK:-/dev/vda}"
SOLILOQUY_ROOT_FALLBACK_FSTYPE="${SOLILOQUY_ROOT_FALLBACK_FSTYPE:-solfs}"
SOLILOQUY_ROOTFS_IMAGE_REQUIRED="${SOLILOQUY_ROOTFS_IMAGE_REQUIRED:-0}"
KERNEL_CMDLINE="${KERNEL_CMDLINE:-quiet loglevel=3 console=tty0 console=ttyS0 random.trust_cpu=on rng_core.default_quality=1000 rdinit=/init soliloquy.ram_root=${SOLILOQUY_RAM_ROOT} soliloquy.ram_root_min_mb=${SOLILOQUY_RAM_ROOT_MIN_MB} soliloquy.root_fallback=${SOLILOQUY_ROOT_FALLBACK} soliloquy.root_fallback_fstype=${SOLILOQUY_ROOT_FALLBACK_FSTYPE}}"

for bin in qemu-system-x86_64; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "missing required tool: ${bin}" >&2
    exit 1
  }
done

if [ ! -f "${KERNEL}" ] || [ ! -f "${INITRAMFS}" ]; then
  echo "missing kernel/initramfs in ${QEMU_DIR} (run fetch-qemu-kernel.sh + build-qemu-initramfs.sh)" >&2
  exit 1
fi

DISPLAY_FLAGS="-display default"
if [ "${QEMU_HEADLESS}" = "1" ]; then
  DISPLAY_FLAGS="-nographic"
elif [ "$(uname -s)" = "Darwin" ]; then
  echo "On macOS - using VNC display. Connect with: open vnc://localhost:5900"
  DISPLAY_FLAGS="-vnc :0 -k en-us"
fi

USE_VIRTIO_GPU="${USE_VIRTIO_GPU:-1}"
RNG_FLAGS=""
if [ "${QEMU_RNG}" = "1" ]; then
  RNG_FLAGS="-object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0"
fi

ROOT_DRIVE_FLAGS=""
if [ -f "${SOLILOQUY_ROOTFS_IMAGE}" ]; then
  echo "Using rootfs image: ${SOLILOQUY_ROOTFS_IMAGE}"
  ROOT_DRIVE_FLAGS="-drive file=${SOLILOQUY_ROOTFS_IMAGE},format=raw,if=none,id=solroot,readonly=on -device virtio-blk-pci,drive=solroot"
elif [ "${SOLILOQUY_ROOTFS_IMAGE_REQUIRED}" = "1" ]; then
  echo "missing required rootfs image: ${SOLILOQUY_ROOTFS_IMAGE}" >&2
  exit 1
fi

GPU_DEVICE="-device virtio-gpu-pci"
VGA="-vga none"
if [ "${USE_VIRTIO_GPU}" = "0" ]; then
  GPU_DEVICE=""
  VGA="-vga virtio"
fi

qemu-system-x86_64 \
  -machine q35,accel="${QEMU_ACCEL}" \
  -m "${QEMU_MEMORY_MB}" \
  -smp 2 \
  -serial mon:stdio \
  ${DISPLAY_FLAGS} \
  ${VGA} \
  ${GPU_DEVICE} \
  -device virtio-keyboard-pci \
  -device virtio-mouse-pci \
  ${RNG_FLAGS} \
  ${ROOT_DRIVE_FLAGS} \
  -device virtio-net-pci,netdev=n1 \
  -netdev user,id=n1 \
  -kernel "${KERNEL}" \
  -initrd "${INITRAMFS}" \
  -append "${KERNEL_CMDLINE}"

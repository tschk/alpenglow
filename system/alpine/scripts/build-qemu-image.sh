#!/bin/sh
set -eu

ROOTFS_DIR="${1:-build/alpine/rootfs}"
OUT_IMG="${2:-build/alpine/qemu/soliloquy-v0.qcow2}"
SIZE="${SIZE:-2G}"

if [ "$(uname -s)" != "Linux" ]; then
  echo "build-qemu-image.sh currently supports Linux hosts only" >&2
  exit 1
fi

for bin in qemu-img mkfs.ext4 mount umount; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "missing required tool: ${bin}" >&2
    exit 1
  }
done

if [ ! -d "${ROOTFS_DIR}" ]; then
  echo "rootfs directory not found: ${ROOTFS_DIR}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT_IMG}")"
RAW_IMG="${OUT_IMG%.qcow2}.raw"
MNT_DIR="$(mktemp -d)"
trap 'sudo umount "${MNT_DIR}" >/dev/null 2>&1 || true; rmdir "${MNT_DIR}" >/dev/null 2>&1 || true' EXIT

qemu-img create -f raw "${RAW_IMG}" "${SIZE}"
mkfs.ext4 -F "${RAW_IMG}"
sudo mount -o loop "${RAW_IMG}" "${MNT_DIR}"
sudo cp -a "${ROOTFS_DIR}/." "${MNT_DIR}/"
sudo mkdir -p "${MNT_DIR}/proc" "${MNT_DIR}/sys" "${MNT_DIR}/dev" "${MNT_DIR}/run"
sudo umount "${MNT_DIR}"

qemu-img convert -f raw -O qcow2 "${RAW_IMG}" "${OUT_IMG}"
rm -f "${RAW_IMG}"

echo "Built QEMU disk image: ${OUT_IMG}"

#!/bin/sh
# Build v86 kernel+initramfs on ultramarine (docker) and pull artifacts back.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOST="${V86_SSH_HOST:-undivisible@192.168.4.134}"
REMOTE="${V86_REMOTE_DIR:-projects/alpenglow}"

command -v ssh >/dev/null 2>&1 || { echo "ssh required" >&2; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo "rsync required" >&2; exit 1; }

echo "→ push sources to ${HOST}:${REMOTE}"
rsync -az --delete \
  --exclude '.git' --exclude 'node_modules' --exclude 'dist' --exclude 'build' \
  --exclude 'target' \
  "${ROOT_DIR}/" "${HOST}:${REMOTE}/"

ALP_VERSION="0.1.$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo 0)"
echo "→ remote build (Alpenglow Linux 7 i686 kernel + initramfs, ${ALP_VERSION})"
ssh -o ConnectTimeout=15 "${HOST}" "cd ${REMOTE} && ALP_VERSION='${ALP_VERSION}' V86_SKIP_SSH=1 V86_KERNEL_DOCKER=1 FORCE_V86_INITRD=1 sh scripts/build-v86-initramfs.sh"

echo "→ pull v86 artifacts"
mkdir -p "${ROOT_DIR}/public/v86"
rsync -az "${HOST}:${REMOTE}/public/v86/alpenglow-v86-initrd.cpio.gz" \
  "${HOST}:${REMOTE}/public/v86/alpenglow-v86-vmlinuz" \
  "${HOST}:${REMOTE}/public/v86/initrd-build-id.txt" \
  "${ROOT_DIR}/public/v86/"

ls -lh "${ROOT_DIR}/public/v86/alpenglow-v86-vmlinuz" "${ROOT_DIR}/public/v86/alpenglow-v86-initrd.cpio.gz"
echo "v86 ssh build ok"
#!/bin/sh
# Build a tiny x86_64 kernel with the FAST initramfs embedded.
# Usage: build-kernel-fast.sh <out-dir> <repo-root>
set -eu

OUT_DIR="${1:?out-dir}"
ROOT_DIR="${2:?repo-root}"
OUT_DIR="$(CDPATH='' cd -- "${OUT_DIR}" && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${ROOT_DIR}" && pwd)"
BACKEND="${ROOT_DIR}/system/backends/appliance"
BOOT_NATIVE="${ROOT_DIR}/scripts/boot-native.sh"
KERNEL_VERSION="${KERNEL_VERSION:-$(grep -E '^KERNEL_VERSION="\${KERNEL_VERSION:-' "${BOOT_NATIVE}" | sed -n 's/.*KERNEL_VERSION:-\([0-9.]*\).*/\1/p')}"
KERNEL_TAR="linux-${KERNEL_VERSION}"
VMLINUZ="${OUT_DIR}/vmlinuz"
INITRAMFS="${OUT_DIR}/initramfs.cpio.lz4"
STAMP="${OUT_DIR}/.kernel-fast.ok"

if [ -f "${STAMP}" ] && [ -f "${VMLINUZ}" ] && [ -f "${INITRAMFS}" ] && [ "${VMLINUZ}" -nt "${INITRAMFS}" ]; then
  echo "  kernel: ${VMLINUZ} (cached, newer than initramfs)"
  exit 0
fi

if [ ! -f "${INITRAMFS}" ]; then
  echo "ERROR: ${INITRAMFS} not found. Build the initramfs first." >&2
  exit 1
fi

echo "→ Building FAST kernel with embedded initramfs (Linux ${KERNEL_VERSION})..."

docker run --rm --platform linux/amd64 \
  -v "${OUT_DIR}:/out" \
  -v "${BACKEND}/kernel:/kcfg:ro" \
  debian:bookworm-slim sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
      libncurses-dev dwarves rsync kmod wget xz-utils ca-certificates >/dev/null
    cd /out
    if [ ! -d "'"${KERNEL_TAR}"'" ]; then
      wget -q "https://cdn.kernel.org/pub/linux/kernel/v7.x/'"${KERNEL_TAR}"'.tar.xz" -O k.tar.xz
      tar -xf k.tar.xz
    fi
    cd "'"${KERNEL_TAR}"'"
    cp /kcfg/alpenglow-qemu-minimal.config .config
    cat /kcfg/lz4.config >> .config 2>/dev/null || true
    cat /kcfg/virt.config >> .config 2>/dev/null || true
    cat /kcfg/fast.config >> .config 2>/dev/null || true
    make ARCH=x86_64 olddefconfig >/dev/null 2>&1
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC 2>/dev/null || true
    make ARCH=x86_64 olddefconfig >/dev/null 2>&1
    echo "→ compiling bzImage (this can take several minutes)..."
    make -j"$(nproc)" ARCH=x86_64 bzImage
    cp arch/x86/boot/bzImage /out/vmlinuz
    touch /out/.kernel-fast.ok
  '

echo "  kernel: ${VMLINUZ}"

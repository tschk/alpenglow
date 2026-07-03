#!/bin/sh
# Build a minimal custom aarch64 kernel for the Alpenglow FAST config.
# Usage: build-kernel-aarch64.sh <out-dir> <repo-root>
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
STAMP="${OUT_DIR}/.kernel-aarch64.ok"

if [ -f "${STAMP}" ] && [ -f "${VMLINUZ}" ]; then
  echo "  kernel: ${VMLINUZ} (cached)"
  exit 0
fi

echo "→ Building custom aarch64 kernel (Linux ${KERNEL_VERSION})..."

docker run --rm --platform linux/amd64 \
  -v "${OUT_DIR}:/out" \
  -v "${BACKEND}/kernel:/kcfg:ro" \
  debian:bookworm-slim sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
      libncurses-dev dwarves rsync kmod wget xz-utils ca-certificates \
      gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu lz4 >/dev/null
    cd /out
    if [ ! -d "'"${KERNEL_TAR}"'" ]; then
      wget -q "https://cdn.kernel.org/pub/linux/kernel/v7.x/'"${KERNEL_TAR}"'.tar.xz" -O k.tar.xz
      tar -xf k.tar.xz
    fi
    cd "'"${KERNEL_TAR}"'"
    make ARCH=arm64 defconfig >/dev/null 2>&1
    cat /kcfg/aarch64-virt.config >> .config 2>/dev/null || true
    cat /kcfg/aarch64-fast.config >> .config 2>/dev/null || true
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >/dev/null 2>&1
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC 2>/dev/null || true
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >/dev/null 2>&1
    echo "→ compiling Image.gz (this can take several minutes)..."
    make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image.gz
    cp arch/arm64/boot/Image.gz /out/vmlinuz
    touch /out/.kernel-aarch64.ok
  '

echo "  kernel: ${VMLINUZ}"

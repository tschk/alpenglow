#!/bin/sh
# Build x86_64 bzImage with virtio-gpu for QEMU graphical boot (Docker; works on macOS hosts).
# Usage: build-kernel-qemu-graphical.sh <out-dir> <alpenglow-repo-root>
set -eu

OUT_DIR="${1:?out-dir}"
ROOT_DIR="${2:?repo root}"
OUT_DIR="$(CDPATH='' cd -- "${OUT_DIR}" && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${ROOT_DIR}" && pwd)"
BACKEND="${ROOT_DIR}/system/backends/appliance"
# Default tracks scripts/boot-native.sh so a kernel bump only has one source of truth.
BOOT_NATIVE="${ROOT_DIR}/scripts/boot-native.sh"
KERNEL_VERSION="${KERNEL_VERSION:-$(grep -E '^KERNEL_VERSION="\$\{KERNEL_VERSION:-' "${BOOT_NATIVE}" | sed -n 's/.*KERNEL_VERSION:-\([0-9.]*\).*/\1/p')}"
KERNEL_TAR="linux-${KERNEL_VERSION}"
VMLINUZ="${OUT_DIR}/vmlinuz"
STAMP="${OUT_DIR}/.kernel-virtio-gpu.ok"

if [ -f "${STAMP}" ] && [ -f "${VMLINUZ}" ]; then
  echo "  kernel: ${VMLINUZ} (cached)"
  exit 0
fi

echo "→ Building kernel in Docker (Linux ${KERNEL_VERSION} + virtio-gpu)..."

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
    cat /kcfg/efi.config >> .config 2>/dev/null || true
    if [ "${KERNEL_UNCOMPRESSED:-0}" = "1" ]; then
      cat /kcfg/uncompressed.config >> .config 2>/dev/null || true
    fi
    if [ "${KERNEL_FASTINIT:-0}" = "1" ]; then
      cat /kcfg/fastinit.config >> .config 2>/dev/null || true
    fi
    echo "CONFIG_DRM_BOCHS_QEMU=y" >> .config
    make ARCH=x86_64 olddefconfig
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC 2>/dev/null || true
    make ARCH=x86_64 olddefconfig
    echo "→ kernel compile (first run: 10–20 min)..."
    make -j"$(nproc)" ARCH=x86_64 bzImage
    cp arch/x86/boot/bzImage /out/vmlinuz
    touch /out/.kernel-virtio-gpu.ok
  '

echo "  kernel: ${VMLINUZ}"
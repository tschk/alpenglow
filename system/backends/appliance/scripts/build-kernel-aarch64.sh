#!/bin/sh
# Build a custom aarch64 kernel for Alpenglow.
# Usage: build-kernel-aarch64.sh <out-dir> <repo-root>
# Profile is selected via KERNEL_PROFILE (fast|minimal|desktop); default is fast.
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
PROFILE="${KERNEL_PROFILE:-fast}"
STAMP="${OUT_DIR}/.kernel-aarch64-${PROFILE}.ok"
JOBS="${AARCH64_KERNEL_JOBS:-4}"

if [ -f "${STAMP}" ] && [ -f "${VMLINUZ}" ]; then
  echo "  kernel: ${VMLINUZ} (cached)"
  exit 0
fi

LOCK="${OUT_DIR}/.kernel-aarch64.lock"
mkdir "${LOCK}" 2>/dev/null || { echo "aarch64 kernel build already running" >&2; exit 1; }
trap 'rmdir "${LOCK}"' EXIT

# Reuse the x86_64 kernel source tarball if already present locally.
NATIVE_SRC="${OUT_DIR}/../../native/${KERNEL_TAR}.tar.xz"
if [ ! -f "${OUT_DIR}/${KERNEL_TAR}.tar.xz" ] && [ -f "${NATIVE_SRC}" ]; then
  cp "${NATIVE_SRC}" "${OUT_DIR}/${KERNEL_TAR}.tar.xz"
  echo "  reusing ${NATIVE_SRC}"
fi

echo "→ Building custom aarch64 ${PROFILE} kernel (Linux ${KERNEL_VERSION})..."
rm -rf "${OUT_DIR}/${KERNEL_TAR}"

docker run --rm --platform linux/amd64 \
  --label alpenglow.aarch64-build=1 \
  -v "${OUT_DIR}:/out" \
  -v "${BACKEND}/kernel:/kcfg:ro" \
  debian:bookworm-slim sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
      libncurses-dev dwarves rsync kmod wget xz-utils ca-certificates python3 \
      gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu lz4
    cd /out
    if [ ! -d "'"${KERNEL_TAR}"'" ]; then
      if [ ! -f '"${KERNEL_TAR}"'.tar.xz ]; then
        wget -q "https://cdn.kernel.org/pub/linux/kernel/v7.x/'"${KERNEL_TAR}"'.tar.xz" -O '"${KERNEL_TAR}"'.tar.xz
      fi
      tar -xf '"${KERNEL_TAR}"'.tar.xz
    fi
    cd "'"${KERNEL_TAR}"'"
    cp /kcfg/alpenglow-virt.config .config

    PROFILE="'"${PROFILE}"'"
    case "${PROFILE}" in
      fast)
        cat /kcfg/aarch64-fast.config >> .config 2>/dev/null || true
        ;;
      minimal)
        cat /kcfg/minimal.config >> .config 2>/dev/null || true
        ;;
      desktop)
        cat /kcfg/desktop.config >> .config 2>/dev/null || true
        ;;
      *)
        echo "unknown kernel profile: ${PROFILE}" >&2
        exit 1
        ;;
    esac

    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >/dev/null 2>&1
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC 2>/dev/null || true
    # Alpine virt config points to a nonexistent signing key; disable module signing.
    ./scripts/config --set-str MODULE_SIG_KEY ""
    ./scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
    ./scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
    ./scripts/config --disable MODULE_SIG --disable MODULE_SIG_ALL --disable MODULE_SIG_SHA256 --disable MODULE_SIG_FORCE --disable MODULE_SIG_VERIFY

    # aarch64 kernels are gzip-compressed; lz4 is not supported for Image.gz
    ./scripts/config --set-str CONFIG_INITRAMFS_SOURCE "/out/initramfs-proper.cpio.lz4"
    ./scripts/config --set-val CONFIG_INITRAMFS_ROOT_UID 0
    ./scripts/config --set-val CONFIG_INITRAMFS_ROOT_GID 0
    ./scripts/config --enable INITRAMFS_COMPRESSION_LZ4

    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig >/dev/null 2>&1
    echo "→ compiling Image.gz (this can take several minutes)..."
    make -j"'"${JOBS}"'" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image.gz
    cp arch/arm64/boot/Image.gz /out/vmlinuz
    touch /out/.kernel-aarch64-'"${PROFILE}"'.ok
  '

echo "  kernel: ${VMLINUZ}"

#!/bin/sh
# Alpenglow Linux bzImage for browser v86 (i686 / 32-bit CPU).
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/v86"
KERNEL_OUT="${ROOT_DIR}/public/v86/alpenglow-v86-vmlinuz"
BACKEND="${ROOT_DIR}/system/backends/appliance"
KERNEL_VERSION="${KERNEL_VERSION:-$(grep -E '^KERNEL_VERSION="\$\{KERNEL_VERSION:-' "${ROOT_DIR}/scripts/boot-native.sh" | sed -n 's/.*KERNEL_VERSION:-\([0-9.]*\).*/\1/p')}"
KERNEL_TAR="linux-${KERNEL_VERSION}"
STAMP="${BUILD_DIR}/.kernel-v86-i686-${KERNEL_VERSION}.ok"

if [ -f "${STAMP}" ] && [ -f "${KERNEL_OUT}" ] && [ "${FORCE_V86_KERNEL:-}" != 1 ]; then
  echo "v86 kernel: ${KERNEL_OUT} (cached)"
  exit 0
fi

mkdir -p "${BUILD_DIR}"

build_in_tree() {
  kdir="$1"
  cross="$2"
  cd "${kdir}"
  make ARCH=i386 i386_defconfig >/dev/null 2>&1
  cat "${BACKEND}/kernel/v86-i686.fragment" >> .config
  cat "${BACKEND}/kernel/v86-i686-fast.fragment" >> .config
  make ARCH=i386 olddefconfig >/dev/null 2>&1
  ./scripts/config --disable DRM --disable SOUND --disable USB_SUPPORT 2>/dev/null || true
  make ARCH=i386 olddefconfig >/dev/null 2>&1
  if [ -n "${cross}" ]; then
    make ARCH=i386 CROSS_COMPILE="${cross}" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)" bzImage
  else
    make ARCH=i386 -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)" bzImage
  fi
  cp arch/x86/boot/bzImage "${BUILD_DIR}/alpenglow-v86-vmlinuz"
}

fetch_kernel() {
  if [ ! -d "${BUILD_DIR}/${KERNEL_TAR}" ]; then
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v7.x/${KERNEL_TAR}.tar.xz" -o "${BUILD_DIR}/k.tar.xz"
    tar -xf "${BUILD_DIR}/k.tar.xz" -C "${BUILD_DIR}"
  fi
}

if [ "${V86_KERNEL_DOCKER:-}" != 1 ] && [ "$(uname -s)" = Linux ]; then
  fetch_kernel
  if command -v i686-linux-gnu-gcc >/dev/null 2>&1; then
    echo "→ v86 kernel: native cross i686-linux-gnu"
    build_in_tree "${BUILD_DIR}/${KERNEL_TAR}" i686-linux-gnu-
    chmod u+w "${KERNEL_OUT}" 2>/dev/null || true
    cp "${BUILD_DIR}/alpenglow-v86-vmlinuz" "${KERNEL_OUT}"
    touch "${STAMP}"
    ls -lh "${KERNEL_OUT}"
    exit 0
  fi
fi

command -v docker >/dev/null 2>&1 || {
  echo "docker required (or Linux + i686-linux-gnu-gcc). Use: V86_SSH=1 sh scripts/build-v86-initramfs.sh" >&2
  exit 1
}

docker run --rm --platform linux/amd64 \
  -v "${BUILD_DIR}:/out" \
  -v "${BACKEND}/kernel:/kcfg:ro" \
  debian:bookworm-slim sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
      libncurses-dev dwarves rsync kmod wget xz-utils zstd ca-certificates \
      gcc-i686-linux-gnu >/dev/null
    cd /out
    if [ ! -d "'"${KERNEL_TAR}"'" ]; then
      wget -q "https://cdn.kernel.org/pub/linux/kernel/v7.x/'"${KERNEL_TAR}"'.tar.xz" -O k.tar.xz
      tar -xf k.tar.xz
    fi
    cd "'"${KERNEL_TAR}"'"
    make ARCH=i386 i386_defconfig >/dev/null 2>&1
    cat /kcfg/v86-i686.fragment >> .config
    cat /kcfg/v86-i686-fast.fragment >> .config
    make ARCH=i386 olddefconfig >/dev/null 2>&1
    ./scripts/config --disable DRM --disable SOUND --disable USB_SUPPORT 2>/dev/null || true
    make ARCH=i386 olddefconfig >/dev/null 2>&1
    make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- -j"$(nproc)" bzImage
    cp arch/x86/boot/bzImage /out/alpenglow-v86-vmlinuz
  '

chmod u+w "${KERNEL_OUT}" 2>/dev/null || true
cp "${BUILD_DIR}/alpenglow-v86-vmlinuz" "${KERNEL_OUT}"
touch "${STAMP}"
ls -lh "${KERNEL_OUT}"

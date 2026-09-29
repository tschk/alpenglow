#!/bin/sh
# Build Alpenglow legacy kernels for machines the i686 image cannot boot.
#
# Each kernel is a defconfig plus the drivers QEMU needs to reach an initramfs
# shell: serial console, initrd, devtmpfs. No network, no graphics, no modules.
# The build runs in Docker because this host has no cross compiler.
#
#   scripts/build-legacy-kernels.sh ppc        # g3beige, 32-bit PowerPC
#   scripts/build-legacy-kernels.sh armv5      # versatilepb, ARM926 (armv5)
#   scripts/build-legacy-kernels.sh i486       # pc, 486 (no i686 requirement)
#   scripts/build-legacy-kernels.sh all
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
KERNEL_VERSION="${KERNEL_VERSION:-7.1.3}"
KERNEL_MAJOR="$(printf '%s' "${KERNEL_VERSION}" | cut -d. -f1)"
SRC_DIR="${REPO_ROOT}/build/legacy/linux-${KERNEL_VERSION}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
require_cmd docker
require_cmd curl

fetch_kernel() {
  if [ -d "${SRC_DIR}" ]; then
    return
  fi
  mkdir -p "${REPO_ROOT}/build/legacy"
  echo "→ fetching linux-${KERNEL_VERSION}"
  curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz" \
    -o "${SRC_DIR}.tar.xz"
  tar -xJf "${SRC_DIR}.tar.xz" -C "${REPO_ROOT}/build/legacy"
  rm -f "${SRC_DIR}.tar.xz"
}

# arch cross image image_path outname fragment
build_one() {
  arch="$1"; cross="$2"; image="$3"; image_path="$4"; outname="$5"; fragment="$6"
  out="${REPO_ROOT}/build/legacy/${outname}"
  if [ -f "${out}" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "  ${outname}: cached"
    return
  fi
  echo "→ building ${outname} (${arch}, ${cross})"
  docker run --rm --platform linux/amd64 \
    -e ARCH="${arch}" -e CROSS="${cross}" -e IMAGE="${image}" -e JOBS="${JOBS}" \
    -v "${SRC_DIR}:/src" \
    -v "${fragment}:/fragment:ro" \
    -v "${REPO_ROOT}/build/legacy:/out" \
    debian:bookworm-slim sh -c '
      set -eu
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
        gcc-'"${cross}"' binutils-'"${cross}"' ca-certificates >/dev/null
      cd /src
      make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- mrproper >/dev/null 2>&1 || true
      make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- defconfig >/dev/null
      cat /fragment >> .config
      make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- olddefconfig >/dev/null
      make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- -j"$(nproc)" '"${image}"'
      cp '"${image_path}"' /out/'"${outname}"'
    '
  ls -lh "${out}"
}

FRAGMENT_DIR="${REPO_ROOT}/system/backends/legacy"

build_ppc() {
  build_one powerpc powerpc-linux-gnu zImage arch/powerpc/boot/zImage \
    zImage-ppc "${FRAGMENT_DIR}/ppc.fragment"
}

build_armv5() {
  build_one arm arm-linux-gnueabi zImage arch/arm/boot/zImage \
    zImage-armv5 "${FRAGMENT_DIR}/armv5.fragment"
}

build_i486() {
  build_one x86 i686-linux-gnu bzImage arch/x86/boot/bzImage \
    bzImage-i486 "${FRAGMENT_DIR}/i486.fragment"
}

fetch_kernel

target="${1:-all}"
case "${target}" in
  ppc) build_ppc ;;
  armv5) build_armv5 ;;
  i486) build_i486 ;;
  all) build_ppc; build_armv5; build_i486 ;;
  *) echo "Usage: $0 {ppc|armv5|i486|all}" >&2; exit 1 ;;
esac

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
KERNEL_VERSION="${KERNEL_VERSION:-7.1}"
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
  # GitHub is far faster than kernel.org from this host. The tag is v7.1,
  # not the 7.1.3 stable tarball name.
  curl -fL "https://github.com/torvalds/linux/archive/refs/tags/v${KERNEL_VERSION}.tar.gz" \
    -o "${SRC_DIR}.tar.gz"
  tar -xzf "${SRC_DIR}.tar.gz" -C "${REPO_ROOT}/build/legacy"
  # GitHub archives unpack to linux-<tag>/, which is what SRC_DIR names.
  rm -f "${SRC_DIR}.tar.gz"
}

# arch cross defconfig image image_path outname fragment
build_one() {
  arch="$1"; cross="$2"; defconfig="$3"; image="$4"; image_path="$5"; outname="$6"; fragment="$7"
  out="${REPO_ROOT}/build/legacy/${outname}"
  if [ -f "${out}" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "  ${outname}: cached"
    return
  fi
  echo "→ building ${outname} (${arch}, ${cross})"
  # alpenglow-cross has the cross compilers already installed.
  # Build it once: docker build -t alpenglow-cross -f scripts/Dockerfile.cross .
  docker run --rm --platform linux/amd64 \
    -v "${SRC_DIR}:/src" \
    -v "${fragment}:/fragment:ro" \
    -v "${REPO_ROOT}/scripts/apply-fragment.sh:/apply-fragment.sh:ro" \
    -v "${REPO_ROOT}/build/legacy:/out" \
    alpenglow-cross sh -c '
      set -eu
      cd /src
      # A fresh tree has nothing to clean, and mrproper walks the whole source
      # tree twice. Skip it unless a previous build left a config behind.
      if [ -f .config ]; then
        make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- mrproper >/dev/null 2>&1 || true
      fi
      make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- '"${defconfig}"' >/dev/null
      # scripts/config overrides symbols defconfig already set. Appending to
      # .config and running olddefconfig keeps the earlier value.
      sh /apply-fragment.sh /fragment
      make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- olddefconfig >/dev/null
      make ARCH='"${arch}"' CROSS_COMPILE='"${cross}"'- -j"$(nproc)" '"${image}"'
      cp '"${image_path}"' /out/'"${outname}"'
    '
  ls -lh "${out}"
}

FRAGMENT_DIR="${REPO_ROOT}/system/backends/legacy"

build_ppc() {
  # pmac32_defconfig is the 32-bit PowerMac config. The generic defconfig is
  # 64-bit, and PPC32 is derived from !PPC64, so it cannot be switched after.
  build_one powerpc powerpc-linux-gnu pmac32_defconfig zImage arch/powerpc/boot/zImage \
    zImage-ppc "${FRAGMENT_DIR}/ppc.fragment"
}

build_armv5() {
  build_one arm arm-linux-gnueabi versatile_defconfig zImage arch/arm/boot/zImage \
    zImage-armv5 "${FRAGMENT_DIR}/armv5.fragment"
}

build_i486() {
  build_one x86 i686-linux-gnu i386_defconfig bzImage arch/x86/boot/bzImage \
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

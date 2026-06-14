#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
OUT_MODULE="${1:-${REPO_ROOT}/build/alpine/qemu/glowfs.ko}"
ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
IMAGE="${GLOWFS_ALPINE_BUILD_IMAGE:-alpine:${ALPINE_VERSION}}"
PLATFORM="${GLOWFS_ALPINE_PLATFORM:-linux/amd64}"
WORK_DIR="${REPO_ROOT}/build/alpine/glowfs-module-work"
KERNEL_DIR="${REPO_ROOT}/system/glowfs/kernel"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build GlowFS against Alpine linux-virt-dev" >&2
  exit 1
fi

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "$(dirname "${OUT_MODULE}")"
cp "${KERNEL_DIR}/Makefile" "${WORK_DIR}/"
cp "${KERNEL_DIR}/Kbuild" "${WORK_DIR}/"
cp "${KERNEL_DIR}/glowfs_format.h" "${WORK_DIR}/"
cp "${KERNEL_DIR}/glowfs_vfs.c" "${WORK_DIR}/"
cp "${KERNEL_DIR}/glowfs_core.rs" "${WORK_DIR}/"

docker run --rm --platform "${PLATFORM}" \
  -v "${WORK_DIR}:/work" \
  -w /work \
  "${IMAGE}" \
  sh -lc '
    set -eu
    apk update >/dev/null
    apk add --no-cache build-base linux-virt-dev >/dev/null
    kernel_release="$(ls /lib/modules | sort | tail -1)"
    make KERNEL_SRC="/lib/modules/${kernel_release}/build" V=0
    test -f glowfs.ko
    printf "%s\n" "${kernel_release}" > glowfs.kernel-release
  '

cp "${WORK_DIR}/glowfs.ko" "${OUT_MODULE}"
cp "${WORK_DIR}/glowfs.kernel-release" "${OUT_MODULE}.kernel-release"
echo "Built GlowFS module: ${OUT_MODULE}"

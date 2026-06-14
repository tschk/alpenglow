#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

IMAGE="${SOLFS_KERNEL_BUILD_IMAGE:-ubuntu:24.04}"

if ! command -v docker >/dev/null 2>&1; then
  printf 'ci-solfs-kernel-module: docker is required\n' >&2
  exit 1
fi

docker run --rm \
  -v "${REPO_ROOT}/system/solfs/kernel:/work" \
  -w /work \
  "${IMAGE}" \
  sh -lc '
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null
    apt-get install -y --no-install-recommends build-essential linux-headers-generic ca-certificates >/dev/null
    kernel_release="$(ls /lib/modules | sort | tail -1)"
    make KERNEL_SRC="/lib/modules/${kernel_release}/build" V=0
    test -f solfs.ko
    make KERNEL_SRC="/lib/modules/${kernel_release}/build" clean >/dev/null
  '

SOLFS_ALPINE_PLATFORM="${SOLFS_ALPINE_PLATFORM:-linux/amd64}" \
  system/alpine/scripts/build-solfs-module.sh "build/alpine/qemu/solfs.ko" >/dev/null
test -f build/alpine/qemu/solfs.ko
test -f build/alpine/qemu/solfs.ko.kernel-release

printf 'ci-solfs-kernel-module: ok\n'

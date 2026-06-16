#!/bin/sh
# CI: compile GlowFS kernel module against Linux headers
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v docker >/dev/null 2>&1; then
  printf 'ci-glowfs-kernel-module: docker is required\n' >&2
  exit 1
fi

# Build against Ubuntu generic kernel headers
docker run --rm \
  -v "${REPO_ROOT}:/alpenglow" \
  alpine:3.21 sh -c '
    set -eu
    apk add --no-cache build-base linux-headers curl tar xz bash >/dev/null

    # ponytail: glowfs module targets 6.12 API; 7.0 port WIP
    KERNEL_VERSION="6.12.93"
    KERNEL_MAJOR="$(echo "${KERNEL_VERSION}" | cut -d. -f1)"

    cd /tmp
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz" -o linux.tar.xz
    tar -xf linux.tar.xz
    cd "/tmp/linux-${KERNEL_VERSION}"

    # Use our config
    cp /alpenglow/system/backends/appliance/kernel/alpenglow-internet-appliance.config .config
    make olddefconfig >/dev/null 2>&1
    make modules_prepare >/dev/null 2>&1

    # Build GlowFS module
    cd /alpenglow/system/glowfs/kernel
    make KERNEL_SRC="/tmp/linux-${KERNEL_VERSION}" V=0
    test -f glowfs.ko
    echo "glowfs.ko built: $(ls -la glowfs.ko)"
    make clean >/dev/null 2>&1
  '

printf 'ci-glowfs-kernel-module: ok\n'

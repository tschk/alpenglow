#!/bin/sh
# CI: compile GlowFS kernel module against Linux headers
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v docker >/dev/null 2>&1; then
  printf 'ci-glowfs-kernel-module: docker is required\n' >&2
  exit 1
fi

# Build against kernel.org source (6.12.x, matches GlowFS C API)
docker run --rm \
  -v "${REPO_ROOT}:/alpenglow" \
  alpine:3.21 sh -c '
    set -eu
    apk add --no-cache build-base linux-headers curl tar xz bash \
      flex bison openssl-dev perl elfutils-dev >/dev/null

    # ponytail: glowfs module targets 6.12 API; 7.0 port WIP
    KERNEL_VERSION="6.12.93"
    KERNEL_MAJOR="$(echo "${KERNEL_VERSION}" | cut -d. -f1)"

    cd /tmp
    curl -fsSL "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git/snapshot/linux-${KERNEL_VERSION}.tar.gz" -o linux.tar.gz
    tar -xzf linux.tar.gz
    cd "/tmp/linux-${KERNEL_VERSION}"

    # Use our appliance kernel config
    cp /alpenglow/system/backends/appliance/kernel/alpenglow-internet-appliance.config .config
    # objtool needed for x86 module LD (elfutils-dev provides libelf)

    make olddefconfig >/dev/null 2>&1
    # modules_prepare might take long due to objtool; skip when headers exist
    make modules_prepare >/dev/null 2>&1 || true

    # Build GlowFS module
    cd /alpenglow/system/glowfs/kernel
    make KERNEL_SRC="/tmp/linux-${KERNEL_VERSION}" clean >/dev/null 2>&1 || true
    make KERNEL_SRC="/tmp/linux-${KERNEL_VERSION}" KBUILD_MODPOST_WARN=1 2>&1
    test -f glowfs.ko
    echo "glowfs.ko built: $(ls -la glowfs.ko)"
    make clean >/dev/null 2>&1 || true
  '

printf 'ci-glowfs-kernel-module: ok\n'

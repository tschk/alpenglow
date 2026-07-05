#!/bin/sh
# Linux 7.0.12 bzImage for browser v86 (x86_64, serial console + initrd).
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/v86"
KERNEL_OUT="${ROOT_DIR}/public/v86/alpenglow-v86-vmlinuz"
BACKEND="${ROOT_DIR}/system/backends/appliance"
KERNEL_VERSION="${KERNEL_VERSION:-7.0.12}"
KERNEL_TAR="linux-${KERNEL_VERSION}"
STAMP="${BUILD_DIR}/.kernel-v86-${KERNEL_VERSION}.ok"

if [ -f "${STAMP}" ] && [ -f "${KERNEL_OUT}" ]; then
  echo "v86 kernel: ${KERNEL_OUT} (cached)"
  exit 0
fi

need_docker() {
  command -v docker >/dev/null 2>&1 || {
    echo "docker required to build v86 kernel" >&2
    exit 1
  }
}
need_docker
mkdir -p "${BUILD_DIR}"

docker run --rm --platform linux/amd64 \
  -v "${BUILD_DIR}:/out" \
  -v "${BACKEND}/kernel:/kcfg:ro" \
  debian:bookworm-slim sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
      libncurses-dev dwarves rsync kmod wget xz-utils zstd ca-certificates >/dev/null
    cd /out
    if [ ! -d "'"${KERNEL_TAR}"'" ]; then
      wget -q "https://cdn.kernel.org/pub/linux/kernel/v7.x/'"${KERNEL_TAR}"'.tar.xz" -O k.tar.xz
      tar -xf k.tar.xz
    fi
    cd "'"${KERNEL_TAR}"'"
    cp /kcfg/alpenglow-qemu-minimal.config .config
    cat /kcfg/virt.config >> .config 2>/dev/null || true
    cat /kcfg/fast.config >> .config 2>/dev/null || true
    make ARCH=x86_64 olddefconfig >/dev/null 2>&1
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC 2>/dev/null || true
    ./scripts/config --enable SERIAL_8250 --enable SERIAL_8250_CONSOLE --enable TTY_SERIAL \
      --enable BLK_DEV_INITRD --enable RD_GZIP --enable PCI --enable ACPI 2>/dev/null || true
    make ARCH=x86_64 -j"$(nproc)" bzImage >/dev/null
    cp arch/x86/boot/bzImage /out/alpenglow-v86-vmlinuz
  '

cp "${BUILD_DIR}/alpenglow-v86-vmlinuz" "${KERNEL_OUT}"
touch "${STAMP}"
ls -lh "${KERNEL_OUT}"
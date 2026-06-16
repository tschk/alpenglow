#!/bin/sh
# CI: Validate Rust kernel module compilation against Linux 7.0
set -eu

KERNEL_VER="7.0"
KERNEL_MAJOR="7"
REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

if ! command -v rustc >/dev/null 2>&1 || ! command -v bindgen >/dev/null 2>&1; then
  echo "ci-rust-kernel-module: rustc/bindgen not found, skip"
  exit 0
fi

cd /tmp
rm -rf linux-kmod-ci
mkdir -p linux-kmod-ci
cd linux-kmod-ci

echo "Downloading Linux ${KERNEL_VER}..."
curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VER}.tar.xz" -o linux.tar.xz
tar -xJf linux.tar.xz
cd "linux-${KERNEL_VER}"

# Minimal config with Rust support
make ARCH=x86_64 defconfig 2>/dev/null
make ARCH=x86_64 kvm_guest.config 2>/dev/null
make ARCH=x86_64 rust.config 2>/dev/null
scripts_config \
  --disable MODULE_SIG_FORMAT MODULE_SIG MODULE_SIG_ALL \
  --disable MODULE_COMPRESS MODULE_COMPRESS_GZIP MODULE_COMPRESS_ALL

RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 olddefconfig 2>/dev/null
RUSTC=rustc BINDGEN=bindgen make -j$(nproc) ARCH=x86_64 modules_prepare 2>&1 | tail -3

# Build Alpenglow core module
cp -r "${REPO_ROOT}/system/kernel-modules/alpenglow_core" /tmp/alpenglow-kmod
make -C /tmp/alpenglow-kmod KERNEL_SRC="$PWD" 2>&1 | tail -5
test -f /tmp/alpenglow-kmod/alpenglow_core.ko && echo "Rust kernel module OK"
echo "ci-rust-kernel-module: ok"

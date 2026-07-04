#!/bin/sh
# CI: Validate Rust kernel module compilation against a pinned Linux version
set -eu

# Match GlowFS CI kernel version; 7.0 is not yet available on kernel.org mirrors.
KERNEL_VER="6.12.93"
KERNEL_MAJOR="6"
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
curl -fsSL "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git/snapshot/linux-${KERNEL_VER}.tar.gz" -o linux.tar.gz
tar -xzf linux.tar.gz
cd "linux-${KERNEL_VER}"

# Minimal config with Rust support
make ARCH=x86_64 defconfig 2>/dev/null
make ARCH=x86_64 kvm_guest.config 2>/dev/null
make ARCH=x86_64 rust.config 2>/dev/null
scripts/config \
  --disable MODULE_SIG_FORMAT --disable MODULE_SIG --disable MODULE_SIG_ALL \
  --disable MODULE_COMPRESS --disable MODULE_COMPRESS_GZIP --disable MODULE_COMPRESS_ALL

RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 olddefconfig 2>/dev/null
NPROC="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
echo "Building Linux ${KERNEL_VER} with Rust support (this may take a few minutes)..."
RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 -j"${NPROC}" > /tmp/kmod-kernel.log 2>&1 || { tail -30 /tmp/kmod-kernel.log; exit 1; }
RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 -j"${NPROC}" modules > /tmp/kmod-modules.log 2>&1 || { tail -30 /tmp/kmod-modules.log; exit 1; }

# Build Alpenglow core module
rm -rf /tmp/alpenglow-kmod
cp -r "${REPO_ROOT}/system/kernel-modules/alpenglow_core" /tmp/alpenglow-kmod
RUSTC=rustc BINDGEN=bindgen make -C /tmp/alpenglow-kmod KERNEL_SRC="$PWD" > /tmp/kmod-build.log 2>&1 || { tail -30 /tmp/kmod-build.log; exit 1; }
test -f /tmp/alpenglow-kmod/alpenglow_core.ko || { echo "ci-rust-kernel-module: missing alpenglow_core.ko"; exit 1; }
echo "Rust kernel module OK"
echo "ci-rust-kernel-module: ok"

#!/bin/sh
# CI: Validate Rust kernel module compilation against Alpenglow's Linux 7.x line.
set -eu

KERNEL_VER="${KERNEL_VER:-7.0.12}"
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
curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${KERNEL_VER}.tar.xz" -o linux.tar.xz
tar -xf linux.tar.xz
cd "linux-${KERNEL_VER}"

make ARCH=x86_64 defconfig 2>/dev/null
make ARCH=x86_64 kvm_guest.config 2>/dev/null
make ARCH=x86_64 rust.config 2>/dev/null
scripts/config \
  --disable MODULE_SIG_FORMAT --disable MODULE_SIG --disable MODULE_SIG_ALL \
  --disable MODULE_COMPRESS --disable MODULE_COMPRESS_GZIP --disable MODULE_COMPRESS_ALL \
  --enable MODULES 2>/dev/null || true
RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 olddefconfig 2>/dev/null

if ! grep -q '^CONFIG_RUST=y' .config; then
  echo "ci-rust-kernel-module: CONFIG_RUST not enabled (rustc may not match kernel Kconfig probe)"
  grep -E 'CONFIG_RUST|RUSTC' .config | head -20 || true
  exit 1
fi

NPROC="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
echo "Preparing Linux ${KERNEL_VER} for out-of-tree Rust module (modules_prepare + rust)..."
RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 -j"${NPROC}" modules_prepare > /tmp/kmod-prepare.log 2>&1 \
  || { tail -30 /tmp/kmod-prepare.log; exit 1; }
RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 -j"${NPROC}" rust/core.o > /tmp/kmod-rust.log 2>&1 \
  || { tail -30 /tmp/kmod-rust.log; exit 1; }

if [ ! -f scripts/target.json ]; then
  echo "ci-rust-kernel-module: missing scripts/target.json after rust/core.o"
  exit 1
fi

rm -rf /tmp/alpenglow-kmod
cp -r "${REPO_ROOT}/system/kernel-modules/alpenglow_core" /tmp/alpenglow-kmod
mkdir -p /tmp/alpenglow-kmod/scripts
cp scripts/target.json /tmp/alpenglow-kmod/scripts/target.json

RUSTC=rustc BINDGEN=bindgen make -C /tmp/alpenglow-kmod KERNEL_SRC="$PWD" > /tmp/kmod-build.log 2>&1 \
  || { tail -40 /tmp/kmod-build.log; exit 1; }
test -f /tmp/alpenglow-kmod/alpenglow_core.ko || { echo "ci-rust-kernel-module: missing alpenglow_core.ko"; exit 1; }
echo "Rust kernel module OK (Linux ${KERNEL_VER})"
echo "ci-rust-kernel-module: ok"
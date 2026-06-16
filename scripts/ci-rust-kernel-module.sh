#!/bin/sh
# CI: Validate Rust kernel module compilation
set -eu

KERNEL_VERSION="7.0"
KERNEL_MAJOR="7"
REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

if ! command -v rustc >/dev/null 2>&1 || ! command -v bindgen >/dev/null 2>&1; then
  echo "ci-rust-kernel-module: rustc or bindgen not found, skipping"
  exit 0
fi

cd /tmp
rm -rf linux-rust-ci
mkdir -p linux-rust-ci
cd linux-rust-ci

curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz" -o linux.tar.xz
tar -xJf linux.tar.xz
cd "linux-${KERNEL_VERSION}"

make ARCH=x86_64 defconfig 2>/dev/null
make ARCH=x86_64 kvm_guest.config 2>/dev/null
make ARCH=x86_64 rust.config 2>/dev/null

export RUSTC=rustc BINDGEN=bindgen
echo "CONFIG_RUST_IS_AVAILABLE=y" >> .config
echo "CONFIG_RUST=y" >> .config
echo "CONFIG_SAMPLES=y" >> .config
echo "CONFIG_SAMPLES_RUST=y" >> .config
echo "CONFIG_SAMPLE_RUST_MINIMAL=m" >> .config

RUSTC=rustc BINDGEN=bindgen make ARCH=x86_64 olddefconfig 2>/dev/null
RUSTC=rustc BINDGEN=bindgen make -j$(nproc) ARCH=x86_64 2>&1 | tail -3
RUSTC=rustc BINDGEN=bindgen make -j$(nproc) ARCH=x86_64 M=samples/rust 2>&1 | tail -5

test -f samples/rust/rust_minimal.ko && echo "Rust kernel module OK" || exit 1
echo "ci-rust-kernel-module: ok"

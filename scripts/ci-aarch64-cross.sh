#!/bin/sh
# Cross-compile aarch64 Zig components (init + kernelctl) without a kernel.
# Full aarch64 QEMU boot requires a pre-built aarch64 kernel image.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_OUT="${REPO_ROOT}/build/cross/aarch64"
mkdir -p "${BUILD_OUT}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
require_cmd zig
require_cmd file

echo "=== aarch64 cross-compile ==="

echo "→ init"
cd "${REPO_ROOT}/system/init"
zig build-exe init.zig -target aarch64-linux-musl -O ReleaseSmall -fstrip -femit-bin="${BUILD_OUT}/zig-init"
file "${BUILD_OUT}/zig-init" | grep -q aarch64 || { echo "ERROR: init not aarch64"; exit 1; }

echo "→ kernelctl"
cd "${REPO_ROOT}/system/kernelctl-zig"
rm -rf zig-out .zig-cache
zig build -Dtarget=aarch64-linux-musl -Drelease=true
cp zig-out/bin/alpenglow-kernelctl "${BUILD_OUT}/alpenglow-kernelctl"
rm -rf zig-out .zig-cache
file "${BUILD_OUT}/alpenglow-kernelctl" | grep -q aarch64 || { echo "ERROR: kernelctl not aarch64"; exit 1; }

echo "ci-aarch64-cross: ok"

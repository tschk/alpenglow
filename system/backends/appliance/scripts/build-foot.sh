#!/bin/sh
# Build foot (Wayland terminal) as static musl binary
set -eu

OUT_DIR="${1:-/build/out}"
VERSION="${2:-1.18.0}"

echo "→ Building foot ${VERSION}..."

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf -- "$BUILD_DIR"' EXIT
cd "$BUILD_DIR"
curl -fsSL "https://codeberg.org/dnkl/foot/archive/v${VERSION}.tar.gz" -o foot.tar.gz
tar -xf foot.tar.gz
cd "foot"

meson setup build \
  -Dprefix=/usr \
  -Ddefault_library=static \
  -Doptimization=s \
  -Db_lto=true \
  -Dtests=false \
  -Ddocs=false

ninja -C build install DESTDIR="${OUT_DIR}/foot"

echo "Done: ${OUT_DIR}/foot"

#!/bin/sh
# Build elogind as static musl binary
set -eu

OUT_DIR="${1:-/tmp/out}"
VERSION="${2:-255.8}"

echo "→ Building elogind ${VERSION}..."

cd /tmp
curl -fsSL "https://github.com/elogind/elogind/archive/v${VERSION}.tar.gz" -o elogind.tar.gz
tar -xf elogind.tar.gz
cd "elogind-${VERSION}"

meson setup build \
  --cross-file /usr/local/share/meson/x86_64-linux-musl.ini 2>/dev/null || \
meson setup build \
  -Dprefix=/usr \
  -Dlibdir=/usr/lib \
  -Dc_link_args="-static" \
  -Dcpp_link_args="-static" \
  -Ddefault_library=static \
  -Dpam=disabled \
  -Dacl=disabled \
  -Dman=disabled \
  -Dtests=false

ninja -C build install DESTDIR="${OUT_DIR}/elogind"

echo "Done: ${OUT_DIR}/elogind"

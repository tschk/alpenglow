#!/bin/sh
# Build iwd as static musl binary
set -eu

OUT_DIR="${1:-/tmp/out}"
VERSION="${2:-2.18}"

echo "→ Building iwd ${VERSION}..."

cd /tmp
curl -fsSL "https://www.kernel.org/pub/linux/network/wireless/iwd-${VERSION}.tar.xz" -o iwd.tar.xz
tar -xf iwd.tar.xz
cd "iwd-${VERSION}"

./configure \
  --prefix=/usr \
  --sysconfdir=/etc \
  --localstatedir=/var \
  --disable-systemd \
  --disable-dbus \
  --enable-static \
  --disable-shared \
  --enable-wired \
  CC="musl-gcc" \
  CFLAGS="-static -Os -s"

make -j"$(nproc)"
make install DESTDIR="${OUT_DIR}/iwd"

echo "Done: ${OUT_DIR}/iwd"

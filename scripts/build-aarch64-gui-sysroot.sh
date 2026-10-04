#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SYSROOT="${ALPENGLOW_AARCH64_GUI_SYSROOT:-${ROOT_DIR}/build/sysroots/aarch64-gui-musl}"
IMAGE="${ALPENGLOW_AARCH64_GUI_SYSROOT_IMAGE:-alpine:3.21}"
CID=""

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing: $1" >&2
    exit 1
  }
}

cleanup() {
  if [ -n "${CID}" ]; then
    docker rm -f "${CID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_cmd docker
require_cmd tar

rm -rf "${SYSROOT}"
mkdir -p "${SYSROOT}"

CID="$(docker create --platform linux/arm64 "${IMAGE}" sleep 600)"
docker start "${CID}" >/dev/null
docker exec "${CID}" sh -lc 'apk add --no-cache musl-dev libstdc++ libstdc++-dev libxkbcommon-dev libxkbcommon-static libxkbcommon-x11 pkgconf fontconfig-dev fontconfig-static freetype-dev freetype-static expat-static zlib-static bzip2-static brotli-static libpng-static libxcb-dev libxcb-static libxau-dev libxdmcp-dev >/dev/null'
docker exec "${CID}" tar -C / -cf - lib usr/include usr/lib | tar -C "${SYSROOT}" -xf -

test -f "${SYSROOT}/usr/lib/libstdc++.a"
test -f "${SYSROOT}/usr/lib/libxkbcommon.a"
test -f "${SYSROOT}/usr/lib/libxkbcommon-x11.a"
for lib in libfontconfig.a libfreetype.a libxcb.a libxcb-xkb.a libXau.a libXdmcp.a; do
  test -f "${SYSROOT}/usr/lib/${lib}"
done
test -f "${SYSROOT}/lib/libc.musl-aarch64.so.1"

printf '%s\n' "${SYSROOT}"

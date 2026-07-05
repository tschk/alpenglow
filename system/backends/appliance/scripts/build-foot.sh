#!/bin/sh
# Build foot (Wayland terminal) as static musl binary
set -eu

OUT_DIR="${1:-/tmp/out}"
VERSION="${2:-1.18.0}"
EXPECTED_SHA256="${3:-}"

if [ -z "${EXPECTED_SHA256}" ]; then
  case "${VERSION}" in
    "1.18.0") EXPECTED_SHA256="9d9f0efe4bca0bbf201482d6e7bb946a12a4b164d2e73dae75a2f2404e1e85ff" ;;
    *) echo "Error: Unknown version ${VERSION} and no expected checksum provided." >&2; exit 1 ;;
  esac
fi

echo "→ Building foot ${VERSION}..."

cd /tmp
# Note: The upstream repository codeberg.org/dnkl/foot/archive/ uses versions without the 'v' prefix
# e.g., 1.18.0 instead of v1.18.0. However, releases before they moved/changed might have it.
# For now, it works without 'v', but we check if it fails and fallback to 'v' if needed, though 1.18.0 requires no 'v'.
curl -fsSL "https://codeberg.org/dnkl/foot/archive/${VERSION}.tar.gz" -o foot.tar.gz || curl -fsSL "https://codeberg.org/dnkl/foot/archive/v${VERSION}.tar.gz" -o foot.tar.gz

ACTUAL_SHA256=$(sha256sum foot.tar.gz | awk '{print $1}')
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
  echo "Error: Checksum mismatch for foot.tar.gz" >&2
  echo "Expected: ${EXPECTED_SHA256}" >&2
  echo "Actual:   ${ACTUAL_SHA256}" >&2
  exit 1
fi

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

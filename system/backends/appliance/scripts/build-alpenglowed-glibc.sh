#!/bin/sh
# Build alpenglowed with glibc dynamic linking (not musl static).
# GPUI uses dlopen() for Wayland/Vulkan libs, which requires dynamic linking.
# Uses Docker rust:latest (glibc) with wayland/xkbcommon dev packages.
#
# Usage: build-alpenglowed-glibc.sh <out-dir> [path-to-alpenglowed-repo]
# Output: $OUT_DIR/alpenglowed-glibc/usr/bin/alpenglowed
set -eu

OUT_DIR="${1:-/build/out}"
[ -d "${OUT_DIR}" ] || mkdir -p "${OUT_DIR}"
OUT_DIR="$(CDPATH='' cd -- "${OUT_DIR}" && pwd)"
ALPENGLOWED_SRC="${2:-}"

# Auto-detect alpenglowed source
if [ -z "${ALPENGLOWED_SRC}" ]; then
  SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
  ROOT_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/../../.." && pwd)"
  for candidate in \
    "${ROOT_DIR}/../alpenglowed" \
    "${ROOT_DIR}/../../alpenglowed"; do
    [ -d "${candidate}/src" ] && { ALPENGLOWED_SRC="${candidate}"; break; }
  done
fi

if [ -z "${ALPENGLOWED_SRC}" ] || [ ! -d "${ALPENGLOWED_SRC}/src" ]; then
  echo "ERROR: alpenglowed source not found. Pass path as 2nd arg." >&2
  exit 1
fi

ALPENGLOWED_SRC="$(CDPATH='' cd -- "${ALPENGLOWED_SRC}" && pwd)"
mkdir -p "${OUT_DIR}/alpenglowed-glibc"

echo "→ Building alpenglowed (glibc, dynamic linking)..."

# Check if crepuscularity repo is a sibling
CREPUS_DIR=""
for candidate in \
  "$(dirname "${ALPENGLOWED_SRC}")/crepuscularity" \
  "$(dirname "$(dirname "${ALPENGLOWED_SRC}")")/crepuscularity"; do
  [ -d "${candidate}/crates" ] && { CREPUS_DIR="${candidate}"; break; }
done

# Mount repos at paths that preserve Cargo.toml relative paths.
# alpenglowed's Cargo.toml uses path = "../crepuscularity/..." so we need
# /build/alpenglowed and /build/crepuscularity inside the container.
DOCKER_VOLUMES="-v ${ALPENGLOWED_SRC}:/build/alpenglowed"
if [ -n "${CREPUS_DIR}" ] && [ -d "${CREPUS_DIR}" ]; then
  CREPUS_DIR="$(CDPATH='' cd -- "${CREPUS_DIR}" && pwd)"
  DOCKER_VOLUMES="${DOCKER_VOLUMES} -v ${CREPUS_DIR}:/build/crepuscularity"
fi

docker run --rm --platform linux/amd64 ${DOCKER_VOLUMES} -v "${OUT_DIR}/alpenglowed-glibc:/out" rust:latest sh -c '
  set -e
  apt-get update -qq 2>/dev/null
  apt-get install -y -qq libwayland-dev libxkbcommon-dev libxkbcommon-x11-dev pkg-config 2>/dev/null >/dev/null

  cd /build/alpenglowed
  cargo build --release --features compositor 2>&1 | tail -5

  mkdir -p /out/usr/bin
  cp target/release/alpenglowed /out/usr/bin/
  chmod 755 /out/usr/bin/alpenglowed

  echo "  alpenglowed: $(file /out/usr/bin/alpenglowed | cut -d, -f1-2)"
'

echo "  output: ${OUT_DIR}/alpenglowed-glibc/usr/bin/alpenglowed"

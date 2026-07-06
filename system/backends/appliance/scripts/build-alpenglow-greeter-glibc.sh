#!/bin/sh
# Build alpenglow-greeter (glibc, dynamic) — separate from alpenglowed shell.
# Usage: build-alpenglow-greeter-glibc.sh <out-dir> [path-to-alpenglowed-repo]
set -eu

OUT_DIR="${1:-/build/out}"
[ -d "${OUT_DIR}" ] || mkdir -p "${OUT_DIR}"
OUT_DIR="$(CDPATH='' cd -- "${OUT_DIR}" && pwd)"
ALPENGLOWED_SRC="${2:-}"

if [ -z "${ALPENGLOWED_SRC}" ]; then
  SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
  ROOT_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/../../.." && pwd)"
  for candidate in \
    "${ROOT_DIR}/../alpenglowed" \
    "${ROOT_DIR}/../../alpenglowed"; do
    [ -d "${candidate}/alpenglow-greeter" ] && { ALPENGLOWED_SRC="${candidate}"; break; }
  done
fi

if [ -z "${ALPENGLOWED_SRC}" ] || [ ! -d "${ALPENGLOWED_SRC}/alpenglow-greeter" ]; then
  echo "ERROR: alpenglow-greeter source not found." >&2
  exit 1
fi

ALPENGLOWED_SRC="$(CDPATH='' cd -- "${ALPENGLOWED_SRC}" && pwd)"
mkdir -p "${OUT_DIR}/alpenglow-greeter-glibc"

DOCKER_VOLUMES="-v ${ALPENGLOWED_SRC}:/build/alpenglowed"

echo "→ Building alpenglow-greeter (glibc)..."

docker run --rm --platform linux/amd64 ${DOCKER_VOLUMES} -v "${OUT_DIR}/alpenglow-greeter-glibc:/out" rust:latest sh -c '
  set -e
  apt-get update -qq 2>/dev/null
  apt-get install -y -qq libwayland-dev libxkbcommon-dev libxkbcommon-x11-dev libfreetype6-dev pkg-config 2>/dev/null >/dev/null
  cd /build/alpenglowed
  sed -i "s#crepuscularity-core = { path = \"../crepuscularity/crates/crepuscularity-core\" }#crepuscularity-core = \"0.4.18\"#" Cargo.toml
  sed -i "s#crepuscularity-gpui = { path = \"../crepuscularity/crates/crepuscularity-gpui\", features = \\[\"wayland\"\\] }#crepuscularity-gpui = { version = \"0.5.0\", features = [\"wayland\"] }#g" Cargo.toml
  sed -i "s#crepuscularity-web = { path = \"../crepuscularity/crates/crepuscularity-web\" }#crepuscularity-web = \"0.4.11\"#" Cargo.toml
  sed -i "s#crepuscularity-gpui = { path = \"../../crepuscularity/crates/crepuscularity-gpui\", features = \\[\"wayland\"\\] }#crepuscularity-gpui = { version = \"0.5.0\", features = [\"wayland\"] }#" alpenglow-greeter/Cargo.toml
  cargo build --release -p alpenglow-greeter
  test -f target/release/alpenglow-greeter
  mkdir -p /out/usr/bin
  cp target/release/alpenglow-greeter /out/usr/bin/
  chmod 755 /out/usr/bin/alpenglow-greeter
'

echo "  output: ${OUT_DIR}/alpenglow-greeter-glibc/usr/bin/alpenglow-greeter"

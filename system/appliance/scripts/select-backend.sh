#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
BACKEND_ID="${1:-${ALPENGLOW_BACKEND:-void-musl-runit}}"

case "${BACKEND_ID}" in
  native|alpenglow-native|appliance)
    BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
    ;;
  void|void-musl-runit)
    BACKEND_DIR="${ROOT_DIR}/system/backends/void"
    ;;
  alpine|alpine-openrc)
    BACKEND_DIR="${ROOT_DIR}/system/alpine"
    ;;
  *)
    echo "unknown backend: ${BACKEND_ID}" >&2
    echo "valid backends: alpenglow-native (default), void-musl-runit, alpine-openrc" >&2
    exit 1
    ;;
esac

if [ ! -d "${BACKEND_DIR}" ]; then
  echo "backend directory not found: ${BACKEND_DIR}" >&2
  exit 1
fi

printf '%s\n' "${BACKEND_DIR}"

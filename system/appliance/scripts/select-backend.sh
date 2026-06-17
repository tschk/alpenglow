#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"

if [ ! -d "${BACKEND_DIR}" ]; then
  echo "backend directory not found: ${BACKEND_DIR}" >&2
  exit 1
fi

printf '%s\n' "${BACKEND_DIR}"

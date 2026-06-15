#!/bin/sh
# Build all Alpenglow userspace services as static musl binaries
# Runs inside Docker alpine:3.21 with build deps
set -eu

OUT_DIR="${1:-/build/out}"
mkdir -p "${OUT_DIR}"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# Steps
${SCRIPT_DIR}/build-dinit.sh "${OUT_DIR}"
${SCRIPT_DIR}/build-toybox.sh "${OUT_DIR}"
${SCRIPT_DIR}/build-elogind.sh "${OUT_DIR}"
${SCRIPT_DIR}/build-iwd.sh "${OUT_DIR}"
${SCRIPT_DIR}/build-greetd.sh "${OUT_DIR}"
${SCRIPT_DIR}/build-velox.sh "${OUT_DIR}"
${SCRIPT_DIR}/build-foot.sh "${OUT_DIR}"

echo "=== All builds complete ==="
ls -la "${OUT_DIR}"

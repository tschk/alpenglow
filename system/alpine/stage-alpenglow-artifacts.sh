#!/bin/bash
# Stage Alpenglow artifacts into rootfs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${PROJECT_ROOT}/build/alpine"
ROOTFS_DIR="${WORK_DIR}/rootfs"
exec "${SCRIPT_DIR}/scripts/stage-alpenglow-artifacts.sh" "${ROOTFS_DIR}"

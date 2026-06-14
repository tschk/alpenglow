#!/bin/bash
# Full build and run Soliloquy v0 in QEMU
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/scripts/qemu-v0.sh" "$@"

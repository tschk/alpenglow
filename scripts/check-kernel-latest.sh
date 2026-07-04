#!/bin/sh
# Check kernel.org for the latest stable release and compare with the
# KERNEL_VERSION pinned in scripts/boot-native.sh. Exit 0 if up to date,
# exit 1 if a bump is available (printing the newer version).
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BOOT_SCRIPT="${REPO_ROOT}/scripts/boot-native.sh"
KERNEL_ORG_URL="https://www.kernel.org/releases.json"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 2; }; }
require_cmd curl
require_cmd jq

CURRENT="${KERNEL_VERSION:-$(grep -E '^KERNEL_VERSION="\$\{KERNEL_VERSION:-' "${BOOT_SCRIPT}" | sed -n 's/.*KERNEL_VERSION:-\([0-9.]*\).*/\1/p')}"
[ -n "${CURRENT}" ] || { echo "Could not determine current KERNEL_VERSION" >&2; exit 2; }

LATEST=$(curl -fsSL "${KERNEL_ORG_URL}" | jq -r '.latest_stable.version')
[ -n "${LATEST}" ] && [ "${LATEST}" != "null" ] || { echo "Could not fetch latest stable from kernel.org" >&2; exit 2; }

if [ "${CURRENT}" = "${LATEST}" ]; then
  echo "kernel: up to date (${CURRENT})"
  exit 0
fi

echo "kernel: bump available: ${CURRENT} -> ${LATEST}"

if [ "${1:-}" = "--apply" ]; then
  sed -i.bak "s/^KERNEL_VERSION=\"\\\${KERNEL_VERSION:-[0-9.]*}/KERNEL_VERSION=\"\\\${KERNEL_VERSION:-${LATEST}}/" "${BOOT_SCRIPT}"
  rm -f "${BOOT_SCRIPT}.bak"
  echo "kernel: updated default in ${BOOT_SCRIPT} to ${LATEST}"
fi

exit 1

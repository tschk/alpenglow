#!/bin/sh
# Unified Alpenglow build entry.
#   ./scripts/build.sh --edition standard --arch x86_64 [--boot]
#   ./scripts/build.sh --edition desktop --arch aarch64
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
EDITION="${ALPENGLOW_EDITION:-standard}"
ARCH="${KERNEL_ARCH:-x86_64}"
BOOT=0
BUILD_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --edition) EDITION="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --boot) BOOT=1; shift ;;
    --build-only) BUILD_ONLY=1; shift ;;
    -h|--help)
      echo "usage: $0 [--edition NAME] [--arch x86_64|aarch64] [--boot] [--build-only]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

export ALPENGLOW_EDITION="$EDITION"
export KERNEL_ARCH="$ARCH"
# shellcheck source=scripts/edition-resolve.sh
. "${ROOT_DIR}/scripts/edition-resolve.sh"

if [ "$ARCH" = "aarch64" ]; then
  case "$EDITION" in
    desktop|desktop-full)
      exec sh "${ROOT_DIR}/scripts/build-aarch64-desktop.sh" "$EDITION"
      ;;
    *)
      exec sh "${ROOT_DIR}/scripts/build-aarch64-fast.sh"
      ;;
  esac
fi

export BUILD_ONLY
if [ "$BOOT" = "1" ]; then
  exec sh "${ROOT_DIR}/scripts/boot-native.sh"
fi
exec sh "${ROOT_DIR}/scripts/boot-native.sh"
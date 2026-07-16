#!/bin/sh
# Append kernel config fragments into .config in the repo-standard order.
# Usage: kernel-merge.sh <kernel-src-dir> <profile> [options]
#   profile: fast | minimal | desktop
# Options (env): KERNEL_UNCOMPRESSED=1 KERNEL_FASTINIT=1 GRAPHICAL=1 ARCH=x86_64|aarch64
set -eu

KERNEL_DIR="${1:?kernel source dir}"
PROFILE="${2:?fast|minimal|desktop}"
ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
KCFG="${ROOT_DIR}/system/backends/appliance/kernel"
ARCH="${ARCH:-${KERNEL_ARCH:-x86_64}}"

cd "$KERNEL_DIR"

if [ "$ARCH" = "aarch64" ]; then
  cp "${KCFG}/alpenglow-virt.config" .config
  cat "${KCFG}/aarch64-fast.config" >> .config 2>/dev/null || true
else
  cp "${KCFG}/alpenglow-qemu-minimal.config" .config
  cat "${KCFG}/lz4.config" >> .config 2>/dev/null || true
  cat "${KCFG}/virt.config" >> .config 2>/dev/null || true
  cat "${KCFG}/strip-down.config" >> .config 2>/dev/null || true
fi

case "$PROFILE" in
  fast) cat "${KCFG}/fast.config" >> .config 2>/dev/null || true ;;
  minimal) cat "${KCFG}/minimal.config" >> .config 2>/dev/null || true ;;
  desktop) cat "${KCFG}/desktop.config" >> .config 2>/dev/null || true ;;
  *)
    echo "kernel-merge: unknown profile ${PROFILE}" >&2
    exit 1
    ;;
esac

if [ "${GRAPHICAL:-0}" = "1" ] || [ "$PROFILE" = "desktop" ]; then
  cat "${KCFG}/virt.config" >> .config 2>/dev/null || true
fi

if [ "${KERNEL_UNCOMPRESSED:-0}" = "1" ]; then
  cat "${KCFG}/uncompressed.config" >> .config 2>/dev/null || true
fi
if [ "${KERNEL_FASTINIT:-0}" = "1" ]; then
  cat "${KCFG}/fastinit.config" >> .config 2>/dev/null || true
fi

make olddefconfig >/dev/null 2>&1 || true
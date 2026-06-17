#!/bin/sh
# Alpenglow — quick start
# Modes: diskless (default) or rootfs (BOOT_MODE=rootfs)
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

case "${1:-help}" in
  build)
    echo "==> Build native boot image (diskless mode)..."
    "${ROOT_DIR}/scripts/boot-native.sh"
    ;;
  build-rootfs)
    echo "==> Build + install to rootfs image..."
    BOOT_MODE=rootfs "${ROOT_DIR}/scripts/boot-native.sh"
    ;;
  boot)
    IMG="${2:-${ROOT_DIR}/build/native/rootfs.img}"
    if [ ! -f "${IMG}" ]; then
      echo "Rootfs image not found. Run ./start.sh build-rootfs first." >&2
      exit 1
    fi
    echo "==> Boot rootfs in QEMU..."
    exec qemu-system-x86_64 -m 512 -smp 2 -nographic -no-reboot \
      -kernel "${ROOT_DIR}/build/native/vmlinuz" \
      -initrd "${ROOT_DIR}/build/native/initramfs.cpio.zst" \
      -drive "file=${IMG},format=raw,if=virtio" \
      -append "quiet console=ttyS0 alpenglow.root=/dev/vda"
    ;;
  install)
    shift
    exec "${ROOT_DIR}/scripts/install-rootfs.sh" "$@"
    ;;
  check)
  bench-all)
    # Multi-OS comparison benchmark (Alpenglow vs Alpine vs others)
    # Requires: x86_64 Linux with KVM. Use ssh ultramarine for meaningful numbers.
    exec "${ROOT_DIR}/scripts/bench-all.sh"
    ;;
  ci-rust)
    exec "${ROOT_DIR}/scripts/ci-rust-core.sh"
    ;;
  ci-os)
    exec "${ROOT_DIR}/scripts/ci-os-appliance.sh"
    ;;
  ci)
    "${ROOT_DIR}/scripts/ci-rust-core.sh"
    "${ROOT_DIR}/scripts/ci-os-appliance.sh"
    echo "ci: ok"
    ;;
  clean)
    cargo clean
    rm -rf "${ROOT_DIR}/build"
    echo "cleaned"
    ;;
  *)
    echo "Usage: $0 <command>"
    echo ""
    echo "  build       Build native boot image (initramfs + kernel)"
    echo "  boot [img]  Boot image in QEMU (default: build/native/alpenglow.img)"
    echo "  check       Cargo check all crates"
    echo "  test        Run all cargo tests"
    echo "  bench       Boot time benchmarks (boot phases + size metrics)"
    echo "  bench-all   Multi-OS comparison (Alpenglow vs Alpine, needs KVM)"
    echo "  ci-rust     Validate Rust crates (CI)"
    echo "  ci-os       Validate OS appliance contract (CI)"
    echo "  ci          Run all CI checks"
    echo "  clean       Clean build artifacts"
    exit 1
    ;;
esac

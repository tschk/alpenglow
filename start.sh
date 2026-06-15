#!/bin/sh
# Alpenglow — quick start
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

case "${1:-help}" in
  build)
    echo "==> Build native boot image..."
    "${ROOT_DIR}/scripts/boot-native.sh"
    ;;
  boot)
    IMG="${2:-${ROOT_DIR}/build/native/alpenglow.img}"
    if [ ! -f "${IMG}" ]; then
      echo "Image not found at ${IMG}. Run ./start.sh build first." >&2
      exit 1
    fi
    echo "==> Boot ${IMG} in QEMU..."
    exec qemu-system-x86_64 -m 512 -smp 2 -drive "file=${IMG},format=raw" -nographic
    ;;
  check)
    exec cargo check
    ;;
  test)
    exec cargo test
    ;;
  bench)
    # Boot-time benchmarks (boot phases + size metrics)
    exec "${ROOT_DIR}/scripts/bench-boot.sh"
    ;;
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

#!/bin/sh
set -eu

ROOTFS="${1:-}"
if [ -z "${ROOTFS}" ]; then
  echo "usage: $0 <rootfs-dir>" >&2
  exit 1
fi

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
SOLILOQUY_DESKTOP_ROOT="${SOLILOQUY_DESKTOP_ROOT:-${REPO_ROOT}/../soliloquy}"
SERVO_BIN="${SERVO_BIN:-${REPO_ROOT}/third_party/servo/target/release/servoshell}"
SERVO_RUNTIME_DIR="${SERVO_RUNTIME_DIR:-}"
SOLD_BIN="${SOLD_BIN:-${REPO_ROOT}/target/release/sold}"
SOL_KERNELCTL_BIN="${SOL_KERNELCTL_BIN:-${REPO_ROOT}/target/release/sol-kernelctl}"
SOL_NETD_BIN="${SOL_NETD_BIN:-${REPO_ROOT}/target/release/sol-netd}"
SOLFS_MODULE="${SOLFS_MODULE:-}"
NATIVE_POLICY_BUILD_SCRIPT="${NATIVE_POLICY_BUILD_SCRIPT:-${REPO_ROOT}/system/alpine/scripts/build-native-policy-modules.sh}"
NATIVE_POLICY_DIR="${NATIVE_POLICY_DIR:-${REPO_ROOT}/build/alpine/native-policy-v}"
NATIVE_POLICY_LIB="${NATIVE_POLICY_LIB:-${NATIVE_POLICY_DIR}/libsoliloquy_native_policy_v.so}"
NATIVE_POLICY_REQUIRED="${NATIVE_POLICY_REQUIRED:-0}"
UI_BUILD_DIR="${UI_BUILD_DIR:-${SOLILOQUY_DESKTOP_ROOT}/ui/desktop/build}"
TARGET_ARCH="${QEMU_ARCH:-x86_64}"

if [ ! -d "${ROOTFS}" ]; then
  echo "rootfs directory not found: ${ROOTFS}" >&2
  exit 1
fi

require_linux_elf_binary() {
  bin_path="$1"
  file_info="$(file "${bin_path}")"
  case "${TARGET_ARCH}" in
    x86_64)
      case "${file_info}" in
        *"ELF 64-bit"*x86-64*) ;;
        *)
          echo "binary is not Linux x86_64 ELF: ${bin_path}" >&2
          echo "detected: ${file_info}" >&2
          echo "build Linux artifacts (not host Mach-O binaries) before staging" >&2
          exit 1
          ;;
      esac
      ;;
    aarch64|arm64)
      case "${file_info}" in
        *"ELF 64-bit"*aarch64*) ;;
        *)
          echo "binary is not Linux aarch64 ELF: ${bin_path}" >&2
          echo "detected: ${file_info}" >&2
          echo "build Linux artifacts (not host Mach-O binaries) before staging" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "unsupported QEMU_ARCH for binary compatibility check: ${TARGET_ARCH}" >&2
      exit 1
      ;;
  esac
}

mkdir -p "${ROOTFS}/usr/local/bin"
mkdir -p "${ROOTFS}/usr/local/share/soliloquy"
if [ ! -f "${SERVO_BIN}" ]; then
  echo "servoshell binary not found at ${SERVO_BIN}" >&2
  echo "expected in-tree fork build artifact; run ensure-servo-fork.sh first" >&2
  exit 1
fi
require_linux_elf_binary "${SERVO_BIN}"
cp "${SERVO_BIN}" "${ROOTFS}/usr/local/bin/servo"
chmod +x "${ROOTFS}/usr/local/bin/servo"

if [ -n "${SERVO_RUNTIME_DIR}" ] && [ -d "${SERVO_RUNTIME_DIR}" ]; then
  cp -R "${SERVO_RUNTIME_DIR}/." "${ROOTFS}/"
elif [ -n "${SERVO_RUNTIME_DIR}" ]; then
  echo "warning: SERVO_RUNTIME_DIR is set but not a directory (${SERVO_RUNTIME_DIR}); skipping glibc bundle copy" >&2
fi

if [ ! -f "${SOLD_BIN}" ]; then
  echo "sold binary not found at ${SOLD_BIN}" >&2
  echo "run cargo build --release -p sold before staging artifacts" >&2
  exit 1
fi
require_linux_elf_binary "${SOLD_BIN}"
cp "${SOLD_BIN}" "${ROOTFS}/usr/local/bin/sold"
chmod +x "${ROOTFS}/usr/local/bin/sold"

if [ -f "${SOL_KERNELCTL_BIN}" ]; then
  require_linux_elf_binary "${SOL_KERNELCTL_BIN}"
  cp "${SOL_KERNELCTL_BIN}" "${ROOTFS}/usr/local/bin/sol-kernelctl"
  chmod +x "${ROOTFS}/usr/local/bin/sol-kernelctl"
fi

if [ -n "${SOLFS_MODULE}" ]; then
  if [ ! -f "${SOLFS_MODULE}" ]; then
    echo "SolFS kernel module not found at ${SOLFS_MODULE}" >&2
    exit 1
  fi
  mkdir -p "${ROOTFS}/usr/local/lib/soliloquy/kernel"
  cp "${SOLFS_MODULE}" "${ROOTFS}/usr/local/lib/soliloquy/kernel/solfs.ko"
  chmod 0644 "${ROOTFS}/usr/local/lib/soliloquy/kernel/solfs.ko"
fi

if [ ! -f "${SOL_NETD_BIN}" ]; then
  echo "sol-netd binary not found at ${SOL_NETD_BIN}" >&2
  echo "run cargo build --release -p sol-netd before staging artifacts" >&2
  exit 1
fi
require_linux_elf_binary "${SOL_NETD_BIN}"
cp "${SOL_NETD_BIN}" "${ROOTFS}/usr/local/bin/sol-netd"
chmod +x "${ROOTFS}/usr/local/bin/sol-netd"

if [ ! -f "${NATIVE_POLICY_LIB}" ] && [ -x "${NATIVE_POLICY_BUILD_SCRIPT}" ]; then
  if ! OUT_DIR="${NATIVE_POLICY_DIR}" "${NATIVE_POLICY_BUILD_SCRIPT}"; then
    if [ "${NATIVE_POLICY_REQUIRED}" = "1" ]; then
      echo "ERROR: failed to build required V native policy userland module" >&2
      exit 1
    fi
    echo "WARNING: V native policy userland module build failed; continuing without it" >&2
  fi
fi

if [ -f "${NATIVE_POLICY_LIB}" ]; then
  native_policy_file_info="$(file "${NATIVE_POLICY_LIB}")"
  native_policy_ok=0
  case "${TARGET_ARCH}" in
    x86_64)
      case "${native_policy_file_info}" in
        *"ELF 64-bit"*"shared object"*x86-64*) native_policy_ok=1 ;;
      esac
      ;;
    aarch64|arm64)
      case "${native_policy_file_info}" in
        *"ELF 64-bit"*"shared object"*aarch64*) native_policy_ok=1 ;;
      esac
      ;;
  esac
  if [ "${native_policy_ok}" = "1" ]; then
    mkdir -p "${ROOTFS}/usr/local/lib/soliloquy/native-policy"
    mkdir -p "${ROOTFS}/usr/local/share/soliloquy/native-policy"
    cp "${NATIVE_POLICY_LIB}" "${ROOTFS}/usr/local/lib/soliloquy/native-policy/libsoliloquy_native_policy_v.so"
    chmod +x "${ROOTFS}/usr/local/lib/soliloquy/native-policy/libsoliloquy_native_policy_v.so"
    if [ -f "${NATIVE_POLICY_DIR}/v.mod" ]; then
      cp "${NATIVE_POLICY_DIR}/v.mod" "${ROOTFS}/usr/local/share/soliloquy/native-policy/v.mod"
    fi
  elif [ "${NATIVE_POLICY_REQUIRED}" = "1" ]; then
    echo "ERROR: V native policy userland module is not a Linux ${TARGET_ARCH} shared object: ${NATIVE_POLICY_LIB}" >&2
    echo "detected: ${native_policy_file_info}" >&2
    exit 1
  else
    echo "WARNING: V native policy userland module is not a Linux ${TARGET_ARCH} shared object; continuing without it" >&2
  fi
elif [ "${NATIVE_POLICY_REQUIRED}" = "1" ]; then
  echo "ERROR: required V native policy userland module not found at ${NATIVE_POLICY_LIB}" >&2
  exit 1
else
  echo "WARNING: V native policy userland module not found; continuing without it" >&2
fi

if [ ! -d "${UI_BUILD_DIR}" ]; then
  echo "desktop UI build not found at ${UI_BUILD_DIR}" >&2
  echo "run tools/soliloquy/build_ui.sh in ${SOLILOQUY_DESKTOP_ROOT} before staging artifacts" >&2
  exit 1
fi
rm -rf "${ROOTFS}/usr/local/share/soliloquy/bundle"
cp -R "${UI_BUILD_DIR}" "${ROOTFS}/usr/local/share/soliloquy/bundle"

# Stage sold bundle (includes os://terminal HTML + ghostty WASM)
BUNDLE_DIR="${REPO_ROOT}/bundle"
GHOSTTY_WASM_REQUIRED="${GHOSTTY_WASM_REQUIRED:-0}"
WASM_OUT="${BUNDLE_DIR}/terminal/ghostty-vt.wasm"
if [ ! -f "${WASM_OUT}" ]; then
  echo "ghostty-vt.wasm not found at ${WASM_OUT}; building now..."
  if command -v zig >/dev/null 2>&1; then
    if ! "${REPO_ROOT}/scripts/build-ghostty-wasm.sh"; then
      if [ "${GHOSTTY_WASM_REQUIRED}" = "1" ]; then
        echo "ERROR: failed to build required ghostty-vt.wasm" >&2
        exit 1
      fi
      echo "WARNING: ghostty-vt.wasm build failed; os://terminal will use JS fallback" >&2
    fi
  else
    if [ "${GHOSTTY_WASM_REQUIRED}" = "1" ]; then
      echo "ERROR: zig not found; cannot build required ghostty-vt.wasm" >&2
      exit 1
    fi
    echo "WARNING: zig not found; os://terminal will use JS fallback" >&2
  fi
fi
mkdir -p "${ROOTFS}/usr/local/share/soliloquy/bundle/terminal"
cp -R "${BUNDLE_DIR}/terminal/." "${ROOTFS}/usr/local/share/soliloquy/bundle/terminal/"
for asset in files.html settings.html files.crepus settings.crepus; do
  if [ -f "${BUNDLE_DIR}/${asset}" ]; then
    cp "${BUNDLE_DIR}/${asset}" "${ROOTFS}/usr/local/share/soliloquy/bundle/${asset}"
  fi
done
if [ -d "${BUNDLE_DIR}/assets" ]; then
  mkdir -p "${ROOTFS}/usr/local/share/soliloquy/bundle/assets"
  cp -R "${BUNDLE_DIR}/assets/." "${ROOTFS}/usr/local/share/soliloquy/bundle/assets/"
fi

echo "Staged servo into ${ROOTFS}"

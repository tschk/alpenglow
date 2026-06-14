#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
EQUILIBRIUM_DIR="${EQUILIBRIUM_DIR:-${ROOT_DIR}/../equilibrium}"
PACKAGE_DIR="${ROOT_DIR}/system/native/kernel-policy-v"
PACKAGE_MANIFEST="${PACKAGE_DIR}/v.mod"
NATIVE_SRC="${PACKAGE_DIR}/policy.v"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/build/alpine/native-policy-v}"
OUT_LIB="${OUT_DIR}/libsoliloquy_native_policy_v.so"
V_TARGET_OS="${V_TARGET_OS:-linux}"

if [ ! -f "${NATIVE_SRC}" ]; then
  echo "missing V policy source: ${NATIVE_SRC}" >&2
  exit 1
fi

if [ ! -f "${PACKAGE_MANIFEST}" ]; then
  echo "missing V package manifest: ${PACKAGE_MANIFEST}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

if [ -x "${EQUILIBRIUM_DIR}/target/release/eq" ]; then
  "${EQUILIBRIUM_DIR}/target/release/eq" check >/dev/null 2>&1 || true
elif [ -f "${EQUILIBRIUM_DIR}/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
  cargo run --manifest-path "${EQUILIBRIUM_DIR}/Cargo.toml" --features cli --bin eq -- check >/dev/null 2>&1 || true
fi

if command -v v >/dev/null 2>&1; then
  if v -shared -prod -gc none -os "${V_TARGET_OS}" -o "${OUT_LIB}" "${NATIVE_SRC}"; then
    if [ -f "${OUT_LIB}" ] && file "${OUT_LIB}" | grep -Eq 'ELF .*shared object'; then
      cp "${PACKAGE_MANIFEST}" "${OUT_DIR}/v.mod"
      echo "Built V native policy userland module: ${OUT_LIB}"
    else
      rm -f "${OUT_LIB}"
      echo "V compiler did not produce a Linux shared object; skipped optional V native policy userland module" >&2
    fi
  else
    echo "V compiler failed; skipped optional V native policy userland module" >&2
  fi
else
  echo "V compiler not found; skipped optional V native policy userland module" >&2
fi

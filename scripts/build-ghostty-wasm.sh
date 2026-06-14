#!/usr/bin/env bash
# Build libghostty-vt as a WebAssembly module for os://terminal.
#
# Output:
#   bundle/terminal/ghostty-vt.wasm   — VT state machine
#
# The wasm module is gitignored (large binary). Run this script:
#   - Manually: ./scripts/build-ghostty-wasm.sh
#   - As part of Alpine staging: system/alpine/scripts/stage-soliloquy-artifacts.sh
#     calls this automatically when the .wasm is absent.
#
# Requirements:
#   - zig 0.15.2 (https://ziglang.org/download/)
#   - third_party/ghostty submodule initialised:
#       git submodule update --init third_party/ghostty
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHOSTTY_DIR="${REPO_ROOT}/third_party/ghostty"
OUT_DIR="${REPO_ROOT}/bundle/terminal"
REQUIRED_ZIG_VERSION="0.15.2"

pick_zig() {
  if [ -n "${GHOSTTY_ZIG:-}" ]; then
    printf '%s\n' "${GHOSTTY_ZIG}"
    return
  fi

  if [ -x /opt/homebrew/opt/zig@0.15/bin/zig ]; then
    printf '%s\n' /opt/homebrew/opt/zig@0.15/bin/zig
    return
  fi

  if command -v zig &>/dev/null; then
    command -v zig
  fi
}

# ── checks ──────────────────────────────────────────────────────────────────
ZIG_BIN="$(pick_zig)"

if [ -z "${ZIG_BIN}" ]; then
  echo "ERROR: zig ${REQUIRED_ZIG_VERSION} not found. Install zig@0.15 or set GHOSTTY_ZIG." >&2
  exit 1
fi

ZIG_VERSION="$("${ZIG_BIN}" version 2>/dev/null || true)"
echo "zig: ${ZIG_VERSION} (${ZIG_BIN})"

if [ "${ZIG_VERSION}" != "${REQUIRED_ZIG_VERSION}" ]; then
  echo "ERROR: ghostty requires zig ${REQUIRED_ZIG_VERSION}; found ${ZIG_VERSION} at ${ZIG_BIN}" >&2
  echo "  Install Homebrew zig@0.15 or set GHOSTTY_ZIG=/path/to/zig-${REQUIRED_ZIG_VERSION}" >&2
  exit 1
fi

if [ ! -f "${GHOSTTY_DIR}/build.zig" ]; then
  echo "ERROR: ${GHOSTTY_DIR}/build.zig not found." >&2
  echo "  Run: git submodule update --init third_party/ghostty" >&2
  exit 1
fi

# ── build ────────────────────────────────────────────────────────────────────
echo "Building ghostty-vt WASM → ${OUT_DIR}/ghostty-vt.wasm"
mkdir -p "${OUT_DIR}"

cd "${GHOSTTY_DIR}"

"${ZIG_BIN}" build \
  -Demit-lib-vt \
  -Dtarget=wasm32-freestanding \
  -Doptimize=ReleaseSmall

# zig-out/bin/ghostty-vt.wasm is the output path documented in ghostty AGENTS.md
WASM_SRC="${GHOSTTY_DIR}/zig-out/bin/ghostty-vt.wasm"

if [ ! -f "${WASM_SRC}" ]; then
  # Fallback: some zig versions put it under lib/
  WASM_SRC="${GHOSTTY_DIR}/zig-out/lib/ghostty-vt.wasm"
fi

if [ ! -f "${WASM_SRC}" ]; then
  echo "ERROR: ghostty-vt.wasm not found after build. Check zig-out/ tree:" >&2
  find "${GHOSTTY_DIR}/zig-out" -name "*.wasm" 2>/dev/null || true
  exit 1
fi

cp "${WASM_SRC}" "${OUT_DIR}/ghostty-vt.wasm"

SIZE="$(du -sh "${OUT_DIR}/ghostty-vt.wasm" | cut -f1)"
echo "OK: ghostty-vt.wasm (${SIZE}) → ${OUT_DIR}/ghostty-vt.wasm"

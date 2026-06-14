#!/bin/sh
set -eu

SOLILOQUY_RUNTIME_STATE_ENV="${SOLILOQUY_RUNTIME_STATE_ENV:-/run/soliloquy/runtime-state.env}"
SOLILOQUY_ZRAM_SIZE="${SOLILOQUY_ZRAM_SIZE:-768M}"

mkdir -p "$(dirname "${SOLILOQUY_RUNTIME_STATE_ENV}")"

record_runtime_state() {
  key="$1"
  value="$2"
  tmp="${SOLILOQUY_RUNTIME_STATE_ENV}.$$"
  if [ -f "${SOLILOQUY_RUNTIME_STATE_ENV}" ]; then
    grep -v "^${key}=" "${SOLILOQUY_RUNTIME_STATE_ENV}" >"${tmp}" || true
  else
    : >"${tmp}"
  fi
  printf '%s=%s\n' "${key}" "${value}" >>"${tmp}"
  mv "${tmp}" "${SOLILOQUY_RUNTIME_STATE_ENV}"
}

if command -v modprobe >/dev/null 2>&1; then
  modprobe zram >/dev/null 2>&1 || true
fi

if [ ! -e /sys/block/zram0 ]; then
  record_runtime_state SOLILOQUY_ZRAM_STATE unavailable
  exit 0
fi

if grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null; then
  record_runtime_state SOLILOQUY_ZRAM_STATE active
  record_runtime_state SOLILOQUY_ZRAM_SIZE "${SOLILOQUY_ZRAM_SIZE}"
  exit 0
fi

if [ -w /sys/block/zram0/comp_algorithm ]; then
  printf 'lz4\n' >/sys/block/zram0/comp_algorithm 2>/dev/null || true
fi
if [ -w /sys/block/zram0/disksize ]; then
  printf '%s\n' "${SOLILOQUY_ZRAM_SIZE}" >/sys/block/zram0/disksize 2>/dev/null || true
fi

if command -v mkswap >/dev/null 2>&1 && command -v swapon >/dev/null 2>&1; then
  mkswap /dev/zram0 >/dev/null 2>&1 || true
  swapon -p 100 /dev/zram0 >/dev/null 2>&1 || true
fi

if grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null; then
  record_runtime_state SOLILOQUY_ZRAM_STATE active
else
  record_runtime_state SOLILOQUY_ZRAM_STATE configured
fi
record_runtime_state SOLILOQUY_ZRAM_SIZE "${SOLILOQUY_ZRAM_SIZE}"

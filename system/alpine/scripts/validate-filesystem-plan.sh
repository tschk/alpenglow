#!/bin/sh
set -eu

ROOTFS="${1:-}"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ALPINE_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_DIR="${ALPINE_DIR}/filesystems"
ROOTFS_LAYOUT="${MANIFEST_DIR}/rootfs-layout.json"
STATE_MOUNTS="${MANIFEST_DIR}/state-mounts.json"

fail() {
  printf 'validate-filesystem-plan: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

assert_contains() {
  file="$1"
  pattern="$2"
  if ! grep -Eq "${pattern}" "${file}"; then
    fail "${file} does not match ${pattern}"
  fi
}

assert_not_contains() {
  file="$1"
  pattern="$2"
  if grep -Eq "${pattern}" "${file}"; then
    fail "${file} unexpectedly matches ${pattern}"
  fi
}

assert_mode() {
  path="$1"
  expected="$2"
  actual="$(stat -c '%a' "${path}" 2>/dev/null || stat -f '%Lp' "${path}")"
  [ "${actual}" = "${expected}" ] || fail "bad mode for ${path}: expected ${expected}, got ${actual}"
}

assert_file "${ROOTFS_LAYOUT}"
assert_file "${STATE_MOUNTS}"
assert_contains "${ROOTFS_LAYOUT}" '"role": "immutable-system"'
assert_contains "${ROOTFS_LAYOUT}" '"solfs"'
assert_contains "${ROOTFS_LAYOUT}" '"erofs"'
assert_contains "${ROOTFS_LAYOUT}" '"squashfs"'
assert_contains "${ROOTFS_LAYOUT}" '"mountpoint": "/"'
assert_contains "${ROOTFS_LAYOUT}" '"state_manifest": "/etc/soliloquy/filesystems/state-mounts.json"'
assert_contains "${STATE_MOUNTS}" '"mountpoint": "/state"'
assert_contains "${STATE_MOUNTS}" '"target": "/home"'
assert_contains "${STATE_MOUNTS}" '"target": "/var/lib/soliloquy"'
assert_contains "${STATE_MOUNTS}" '"target": "/var/cache/soliloquy"'
assert_contains "${STATE_MOUNTS}" '"target": "/var/log/soliloquy"'
assert_not_contains "${STATE_MOUNTS}" '"target": "/etc"|"/state/etc"|"/state/usr"|"/state/opt"'

if [ -n "${ROOTFS}" ]; then
  assert_dir "${ROOTFS}"
  assert_file "${ROOTFS}/etc/soliloquy/filesystems/rootfs-layout.json"
  assert_file "${ROOTFS}/etc/soliloquy/filesystems/state-mounts.json"
  assert_contains "${ROOTFS}/etc/soliloquy/system.json" '"immutable_root": true'
  assert_contains "${ROOTFS}/etc/soliloquy/system.json" '"state_root": "/state"'
  assert_contains "${ROOTFS}/etc/soliloquy/system.json" '"rootfs_layout": "/etc/soliloquy/filesystems/rootfs-layout.json"'
  assert_file "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan"
  assert_contains "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" '^soliloquy-root / solfs ro,nodev 0 0$'
  assert_contains "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" '^soliloquy-state /state ext4 rw,nosuid,nodev 0 2$'
  assert_contains "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" '^/state/home /home none bind 0 0$'
  assert_contains "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" '^/state/var/lib/soliloquy /var/lib/soliloquy none bind 0 0$'
  assert_contains "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" '^/state/var/cache/soliloquy /var/cache/soliloquy none bind 0 0$'
  assert_contains "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" '^/state/var/log/soliloquy /var/log/soliloquy none bind 0 0$'
  for dir in \
    "${ROOTFS}/home" \
    "${ROOTFS}/state" \
    "${ROOTFS}/sysroot/soliloquy" \
    "${ROOTFS}/var/lib/soliloquy" \
    "${ROOTFS}/var/cache/soliloquy" \
    "${ROOTFS}/var/log/soliloquy"
  do
    assert_dir "${dir}"
  done
  assert_mode "${ROOTFS}/state" 700
  assert_mode "${ROOTFS}/var/lib/soliloquy/browser/profiles" 700
  assert_mode "${ROOTFS}/var/lib/soliloquy/system" 700
  assert_mode "${ROOTFS}/var/cache/soliloquy" 700
  assert_mode "${ROOTFS}/var/log/soliloquy" 700
fi

printf 'validate-filesystem-plan: ok\n'

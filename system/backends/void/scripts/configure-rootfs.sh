#!/bin/sh
set -eu

ROOTFS="${1:-}"
if [ -z "${ROOTFS}" ]; then
  echo "usage: $0 <rootfs-dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
BACKEND_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${BACKEND_DIR}/../../.." && pwd)"
ALPINE_DIR="${ROOT_DIR}/system/alpine"
OVERLAY_DIR="${ALPINE_DIR}/rootfs-overlay"
FILESYSTEM_MANIFEST_DIR="${ROOT_DIR}/system/appliance/filesystems"
BIN_SRC="${ALPINE_DIR}/scripts"
SOLILOQUY_UID="770"
SOLILOQUY_GID="770"
SOLD_UID="771"
SOLD_GID="771"

if [ ! -d "${ROOTFS}" ]; then
  echo "rootfs directory not found: ${ROOTFS}" >&2
  exit 1
fi

ensure_group() {
  name="$1"
  gid="$2"
  if ! grep -q "^${name}:" "${ROOTFS}/etc/group" 2>/dev/null; then
    printf '%s:x:%s:\n' "${name}" "${gid}" >>"${ROOTFS}/etc/group"
  fi
}

ensure_user() {
  name="$1"
  uid="$2"
  gid="$3"
  home="$4"
  if ! grep -q "^${name}:" "${ROOTFS}/etc/passwd" 2>/dev/null; then
    printf '%s:x:%s:%s:%s:%s:/sbin/nologin\n' "${name}" "${uid}" "${gid}" "${name}" "${home}" >>"${ROOTFS}/etc/passwd"
  fi
}

ensure_group "soliloquy" "${SOLILOQUY_GID}"
ensure_group "sold" "${SOLD_GID}"
ensure_user "soliloquy" "${SOLILOQUY_UID}" "${SOLILOQUY_GID}" "/var/lib/soliloquy"
ensure_user "sold" "${SOLD_UID}" "${SOLD_GID}" "/var/lib/soliloquy/system"

mkdir -p "${ROOTFS}/etc/soliloquy/filesystems"
mkdir -p "${ROOTFS}/etc/soliloquy/services"
mkdir -p "${ROOTFS}/etc/soliloquy/generations"
mkdir -p "${ROOTFS}/var/lib/soliloquy/oil"
mkdir -p "${ROOTFS}/etc/runit/runsvdir/default"
mkdir -p "${ROOTFS}/etc/sv"
mkdir -p "${ROOTFS}/usr/local/bin"
mkdir -p "${ROOTFS}/home" "${ROOTFS}/state" "${ROOTFS}/sysroot/soliloquy"
mkdir -p \
  "${ROOTFS}/var/lib/soliloquy/browser/profiles" \
  "${ROOTFS}/var/lib/soliloquy/browser/cache" \
  "${ROOTFS}/var/lib/soliloquy/browser/downloads" \
  "${ROOTFS}/var/lib/soliloquy/browser/state" \
  "${ROOTFS}/var/lib/soliloquy/browser/logs" \
  "${ROOTFS}/var/lib/soliloquy/browser/terminal" \
  "${ROOTFS}/var/lib/soliloquy/files" \
  "${ROOTFS}/var/lib/soliloquy/system" \
  "${ROOTFS}/var/lib/soliloquy/system/plugins" \
  "${ROOTFS}/var/lib/soliloquy/wax"
mkdir -p "${ROOTFS}/var/cache/soliloquy" "${ROOTFS}/var/log/soliloquy"

chmod 700 "${ROOTFS}/state"
chmod 700 \
  "${ROOTFS}/var/lib/soliloquy/browser/profiles" \
  "${ROOTFS}/var/lib/soliloquy/browser/cache" \
  "${ROOTFS}/var/lib/soliloquy/browser/downloads" \
  "${ROOTFS}/var/lib/soliloquy/browser/state" \
  "${ROOTFS}/var/lib/soliloquy/browser/logs" \
  "${ROOTFS}/var/lib/soliloquy/browser/terminal" \
  "${ROOTFS}/var/lib/soliloquy/files" \
  "${ROOTFS}/var/lib/soliloquy/system" \
  "${ROOTFS}/var/lib/soliloquy/system/plugins" \
  "${ROOTFS}/var/cache/soliloquy" \
  "${ROOTFS}/var/log/soliloquy"

chown -R "${SOLILOQUY_UID}:${SOLILOQUY_GID}" "${ROOTFS}/var/lib/soliloquy/browser" >/dev/null 2>&1 || true
chown -R "${SOLILOQUY_UID}:${SOLILOQUY_GID}" "${ROOTFS}/var/cache/soliloquy" >/dev/null 2>&1 || true
chown -R "${SOLD_UID}:${SOLD_GID}" "${ROOTFS}/var/lib/soliloquy/files" "${ROOTFS}/var/lib/soliloquy/system" >/dev/null 2>&1 || true

cp -R "${OVERLAY_DIR}/." "${ROOTFS}/"
cp "${BIN_SRC}/apply-kernel-policy.sh" "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh"
cp "${BIN_SRC}/apply-pressure-policy.sh" "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh"
cp "${BIN_SRC}/apply-zram-policy.sh" "${ROOTFS}/usr/local/bin/apply-zram-policy.sh"
cp "${BIN_SRC}/sol-session-start" "${ROOTFS}/usr/local/bin/sol-session-start"
cp "${BIN_SRC}/sol-servo-wrapper" "${ROOTFS}/usr/local/bin/sol-servo-wrapper"
cp "${FILESYSTEM_MANIFEST_DIR}/rootfs-layout.json" "${ROOTFS}/etc/soliloquy/filesystems/rootfs-layout.json"
cp "${FILESYSTEM_MANIFEST_DIR}/state-mounts.json" "${ROOTFS}/etc/soliloquy/filesystems/state-mounts.json"
cp "${BACKEND_DIR}/backend.json" "${ROOTFS}/etc/soliloquy/backend.json"
cp "${BACKEND_DIR}/packages-runtime.txt" "${ROOTFS}/etc/soliloquy/world.void"
cp "${BACKEND_DIR}/packages-dev.txt" "${ROOTFS}/etc/soliloquy/world.void.dev"
cp "${BACKEND_DIR}/packages-runtime.txt" "${ROOTFS}/etc/soliloquy/world"
cp -R "${BACKEND_DIR}/runit/." "${ROOTFS}/etc/sv/"
rm -rf "${ROOTFS}/etc/apk"

for service in seatd sol-kernel-policy sol-netd sol-zram sold sol-session; do
  ln -s "/etc/sv/${service}" "${ROOTFS}/etc/runit/runsvdir/default/${service}" 2>/dev/null || true
done

chmod +x \
  "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-zram-policy.sh" \
  "${ROOTFS}/usr/local/bin/soliloquy-generation-mark-good" \
  "${ROOTFS}/usr/local/bin/sol-session-start" \
  "${ROOTFS}/usr/local/bin/sol-servo-wrapper" \
  "${ROOTFS}/init"

find "${ROOTFS}/etc/sv" -name run -exec chmod +x {} \;

cat > "${ROOTFS}/etc/inittab" <<'EOF'
::sysinit:/etc/runit/1
::wait:/etc/runit/2
::ctrlaltdel:/etc/runit/ctrlaltdel
::shutdown:/etc/runit/3
EOF

cat > "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" <<'EOF'
soliloquy-root / solfs ro,nodev 0 0
soliloquy-ram-root / ramfs auto,min_ram_mb=3072,fallback=/dev/vda 0 0
soliloquy-state /state ext4 rw,nosuid,nodev 0 2
tmpfs /run tmpfs nosuid,nodev,mode=0755 0 0
tmpfs /tmp tmpfs nosuid,nodev,mode=0755 0 0
tmpfs /dev/shm tmpfs nosuid,nodev,mode=1777,size=256m 0 0
/state/home /home none bind 0 0
/state/var/lib/soliloquy /var/lib/soliloquy none bind 0 0
/state/var/cache/soliloquy /var/cache/soliloquy none bind 0 0
/state/var/log/soliloquy /var/log/soliloquy none bind 0 0
EOF

cat > "${ROOTFS}/etc/soliloquy/system.json" <<'EOF'
{
  "backend": "void-musl-runit",
  "composition_model": "oasis-static",
  "filesystem": {
    "immutable_root": true,
    "rootfs_layout": "/etc/soliloquy/filesystems/rootfs-layout.json",
    "state_mounts": "/etc/soliloquy/filesystems/state-mounts.json",
    "state_root": "/state"
  },
  "service_manager": {
    "id": "runit",
    "runsvdir": "/etc/runit/runsvdir/default"
  },
  "package_manager": {
    "id": "xbps",
    "mode": "composition-only",
    "runtime_mutation": false
  }
}
EOF

printf 'Configured Void musl runit rootfs at %s\n' "${ROOTFS}"

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
ALPENGLOW_UID="770"
ALPENGLOW_GID="770"
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

ensure_group "alpenglow" "${ALPENGLOW_GID}"
ensure_group "sold" "${SOLD_GID}"
ensure_user "alpenglow" "${ALPENGLOW_UID}" "${ALPENGLOW_GID}" "/var/lib/alpenglow"
ensure_user "sold" "${SOLD_UID}" "${SOLD_GID}" "/var/lib/alpenglow/system"

mkdir -p "${ROOTFS}/etc/alpenglow/filesystems"
mkdir -p "${ROOTFS}/etc/alpenglow/services"
mkdir -p "${ROOTFS}/etc/alpenglow/generations"
mkdir -p "${ROOTFS}/var/lib/alpenglow/oil"
mkdir -p "${ROOTFS}/etc/runit/runsvdir/default"
mkdir -p "${ROOTFS}/etc/sv"
mkdir -p "${ROOTFS}/usr/local/bin"
mkdir -p "${ROOTFS}/home" "${ROOTFS}/state" "${ROOTFS}/sysroot/alpenglow"
mkdir -p \
  "${ROOTFS}/var/lib/alpenglow/browser/profiles" \
  "${ROOTFS}/var/lib/alpenglow/browser/cache" \
  "${ROOTFS}/var/lib/alpenglow/browser/downloads" \
  "${ROOTFS}/var/lib/alpenglow/browser/state" \
  "${ROOTFS}/var/lib/alpenglow/browser/logs" \
  "${ROOTFS}/var/lib/alpenglow/browser/terminal" \
  "${ROOTFS}/var/lib/alpenglow/files" \
  "${ROOTFS}/var/lib/alpenglow/system" \
  "${ROOTFS}/var/lib/alpenglow/system/plugins" \
  "${ROOTFS}/var/lib/alpenglow/oil"
mkdir -p "${ROOTFS}/var/cache/alpenglow" "${ROOTFS}/var/log/alpenglow"

chmod 700 "${ROOTFS}/state"
chmod 700 \
  "${ROOTFS}/var/lib/alpenglow/browser/profiles" \
  "${ROOTFS}/var/lib/alpenglow/browser/cache" \
  "${ROOTFS}/var/lib/alpenglow/browser/downloads" \
  "${ROOTFS}/var/lib/alpenglow/browser/state" \
  "${ROOTFS}/var/lib/alpenglow/browser/logs" \
  "${ROOTFS}/var/lib/alpenglow/browser/terminal" \
  "${ROOTFS}/var/lib/alpenglow/files" \
  "${ROOTFS}/var/lib/alpenglow/system" \
  "${ROOTFS}/var/lib/alpenglow/system/plugins" \
  "${ROOTFS}/var/cache/alpenglow" \
  "${ROOTFS}/var/log/alpenglow"

chown -R "${ALPENGLOW_UID}:${ALPENGLOW_GID}" "${ROOTFS}/var/lib/alpenglow/browser" >/dev/null 2>&1 || true
chown -R "${ALPENGLOW_UID}:${ALPENGLOW_GID}" "${ROOTFS}/var/cache/alpenglow" >/dev/null 2>&1 || true
chown -R "${SOLD_UID}:${SOLD_GID}" "${ROOTFS}/var/lib/alpenglow/files" "${ROOTFS}/var/lib/alpenglow/system" >/dev/null 2>&1 || true

cp -R "${OVERLAY_DIR}/." "${ROOTFS}/"
cp "${BIN_SRC}/apply-kernel-policy.sh" "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh"
cp "${BIN_SRC}/apply-pressure-policy.sh" "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh"
cp "${BIN_SRC}/apply-zram-policy.sh" "${ROOTFS}/usr/local/bin/apply-zram-policy.sh"
cp "${BIN_SRC}/alpenglow-session-start" "${ROOTFS}/usr/local/bin/alpenglow-session-start"
cp "${BIN_SRC}/alpenglow-servo-wrapper" "${ROOTFS}/usr/local/bin/alpenglow-servo-wrapper"
cp "${FILESYSTEM_MANIFEST_DIR}/rootfs-layout.json" "${ROOTFS}/etc/alpenglow/filesystems/rootfs-layout.json"
cp "${FILESYSTEM_MANIFEST_DIR}/state-mounts.json" "${ROOTFS}/etc/alpenglow/filesystems/state-mounts.json"
cp "${BACKEND_DIR}/backend.json" "${ROOTFS}/etc/alpenglow/backend.json"
cp "${BACKEND_DIR}/packages-runtime.txt" "${ROOTFS}/etc/alpenglow/world.void"
cp "${BACKEND_DIR}/packages-dev.txt" "${ROOTFS}/etc/alpenglow/world.void.dev"
cp "${BACKEND_DIR}/packages-runtime.txt" "${ROOTFS}/etc/alpenglow/world"
cp -R "${BACKEND_DIR}/runit/." "${ROOTFS}/etc/sv/"
rm -rf "${ROOTFS}/etc/apk"

for service in seatd alpenglow-kernel-policy alpenglow-netd alpenglow-zram sold alpenglow-session; do
  ln -s "/etc/sv/${service}" "${ROOTFS}/etc/runit/runsvdir/default/${service}" 2>/dev/null || true
done

chmod +x \
  "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-zram-policy.sh" \
  "${ROOTFS}/usr/local/bin/alpenglow-generation-mark-good" \
  "${ROOTFS}/usr/local/bin/alpenglow-session-start" \
  "${ROOTFS}/usr/local/bin/alpenglow-servo-wrapper" \
  "${ROOTFS}/init"

find "${ROOTFS}/etc/sv" -name run -exec chmod +x {} \;

cat > "${ROOTFS}/etc/inittab" <<'EOF'
::sysinit:/etc/runit/1
::wait:/etc/runit/2
::ctrlaltdel:/etc/runit/ctrlaltdel
::shutdown:/etc/runit/3
EOF

cat > "${ROOTFS}/etc/alpenglow/filesystems/fstab.plan" <<'EOF'
alpenglow-root / glowfs ro,nodev 0 0
alpenglow-ram-root / ramfs auto,min_ram_mb=3072,fallback=/dev/vda 0 0
alpenglow-state /state ext4 rw,nosuid,nodev 0 2
tmpfs /run tmpfs nosuid,nodev,mode=0755 0 0
tmpfs /tmp tmpfs nosuid,nodev,mode=0755 0 0
tmpfs /dev/shm tmpfs nosuid,nodev,mode=1777,size=256m 0 0
/state/home /home none bind 0 0
/state/var/lib/alpenglow /var/lib/alpenglow none bind 0 0
/state/var/cache/alpenglow /var/cache/alpenglow none bind 0 0
/state/var/log/alpenglow /var/log/alpenglow none bind 0 0
EOF

cat > "${ROOTFS}/etc/alpenglow/system.json" <<'EOF'
{
  "backend": "void-musl-runit",
  "composition_model": "oasis-static",
  "filesystem": {
    "immutable_root": true,
    "rootfs_layout": "/etc/alpenglow/filesystems/rootfs-layout.json",
    "state_mounts": "/etc/alpenglow/filesystems/state-mounts.json",
    "state_root": "/state"
  },
  "service_manager": {
    "id": "runit",
    "runsvdir": "/etc/runit/runsvdir/default"
  },
  "package_manager": {
    "id": "oil",
    "mode": "composition-only",
    "binary": "/usr/local/bin/wax",
    "state_root": "/var/lib/alpenglow/oil",
    "bootstrap": "xbps",
    "runtime_mutation": false
  }
}
EOF

printf 'Configured Void musl runit rootfs at %s\n' "${ROOTFS}"

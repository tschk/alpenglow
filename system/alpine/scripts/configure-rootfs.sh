#!/bin/sh
set -eu

ROOTFS="${1:-}"
if [ -z "${ROOTFS}" ]; then
  echo "usage: $0 <rootfs-dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ALPINE_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
OVERLAY_DIR="${ALPINE_DIR}/rootfs-overlay"
OPENRC_DIR="${ALPINE_DIR}/openrc"
BIN_SRC="${ALPINE_DIR}/scripts"
SERVICE_REGISTRY_SRC="${ALPINE_DIR}/services.json"
KERNEL_POLICY_SRC="${ALPINE_DIR}/kernel-policy.json"
FILESYSTEM_MANIFEST_DIR="${ALPINE_DIR}/filesystems"
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

ensure_shadow() {
  name="$1"
  if [ -f "${ROOTFS}/etc/shadow" ] && ! grep -q "^${name}:" "${ROOTFS}/etc/shadow" 2>/dev/null; then
    printf '%s:!::0:::::\n' "${name}" >>"${ROOTFS}/etc/shadow"
  fi
}

ensure_group "alpenglow" "${ALPENGLOW_GID}"
ensure_group "sold" "${SOLD_GID}"
ensure_user "alpenglow" "${ALPENGLOW_UID}" "${ALPENGLOW_GID}" "/var/lib/alpenglow"
ensure_user "sold" "${SOLD_UID}" "${SOLD_GID}" "/var/lib/alpenglow/system"
ensure_shadow "alpenglow"
ensure_shadow "sold"

mkdir -p "${ROOTFS}/etc/init.d" "${ROOTFS}/usr/local/bin"
mkdir -p "${ROOTFS}/etc/local.d"
mkdir -p "${ROOTFS}/etc/network"
mkdir -p "${ROOTFS}/etc/alpenglow/filesystems"
mkdir -p "${ROOTFS}/etc/alpenglow/plugins"
mkdir -p "${ROOTFS}/etc/alpenglow/services"
mkdir -p "${ROOTFS}/etc/alpenglow/generations"
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

mkdir -p "${ROOTFS}/tmp"
chmod 755 "${ROOTFS}/tmp"

cp -R "${OVERLAY_DIR}/." "${ROOTFS}/"
cp "${OPENRC_DIR}/seatd" "${ROOTFS}/etc/init.d/seatd"
cp "${OPENRC_DIR}/alpenglow-kernel-policy" "${ROOTFS}/etc/init.d/alpenglow-kernel-policy"
cp "${OPENRC_DIR}/alpenglow-netd" "${ROOTFS}/etc/init.d/alpenglow-netd"
cp "${OPENRC_DIR}/alpenglow-pressure" "${ROOTFS}/etc/init.d/alpenglow-pressure"
cp "${OPENRC_DIR}/alpenglow-zram" "${ROOTFS}/etc/init.d/alpenglow-zram"
cp "${OPENRC_DIR}/alpenglow-session" "${ROOTFS}/etc/init.d/alpenglow-session"
if [ -f "${OPENRC_DIR}/sold" ]; then
  cp "${OPENRC_DIR}/sold" "${ROOTFS}/etc/init.d/sold"
fi
cp "${BIN_SRC}/apply-kernel-policy.sh" "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh"
cp "${BIN_SRC}/apply-pressure-policy.sh" "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh"
cp "${BIN_SRC}/apply-zram-policy.sh" "${ROOTFS}/usr/local/bin/apply-zram-policy.sh"
cp "${BIN_SRC}/alpenglow-session-start" "${ROOTFS}/usr/local/bin/alpenglow-session-start"
cp "${BIN_SRC}/alpenglow-servo-wrapper" "${ROOTFS}/usr/local/bin/alpenglow-servo-wrapper"
cp "${FILESYSTEM_MANIFEST_DIR}/rootfs-layout.json" "${ROOTFS}/etc/alpenglow/filesystems/rootfs-layout.json"
cp "${FILESYSTEM_MANIFEST_DIR}/state-mounts.json" "${ROOTFS}/etc/alpenglow/filesystems/state-mounts.json"

chmod +x \
  "${ROOTFS}/etc/init.d/seatd" \
  "${ROOTFS}/etc/init.d/alpenglow-kernel-policy" \
  "${ROOTFS}/etc/init.d/alpenglow-netd" \
  "${ROOTFS}/etc/init.d/alpenglow-pressure" \
  "${ROOTFS}/etc/init.d/alpenglow-zram" \
  "${ROOTFS}/etc/init.d/alpenglow-session" \
  "${ROOTFS}/etc/init.d/sold" \
  "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-zram-policy.sh" \
  "${ROOTFS}/usr/local/bin/alpenglow-generation-mark-good" \
  "${ROOTFS}/usr/local/bin/alpenglow-session-start" \
  "${ROOTFS}/usr/local/bin/alpenglow-servo-wrapper" \
  "${ROOTFS}/init"

if [ -f "${ALPINE_DIR}/packages-v0.txt" ]; then
  cp "${ALPINE_DIR}/packages-v0.txt" "${ROOTFS}/etc/apk/world.alpenglow"
fi
if [ -f "${ALPINE_DIR}/packages-v0-dev.txt" ]; then
  cp "${ALPINE_DIR}/packages-v0-dev.txt" "${ROOTFS}/etc/apk/world.alpenglow.dev"
fi

cat > "${ROOTFS}/etc/rc.conf" <<'EOF'
rc_logger="NO"
rc_parallel="YES"
rc_quiet_openrc="YES"
EOF

cat > "${ROOTFS}/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

mkdir -p "${ROOTFS}/etc/udhcpc"
cat > "${ROOTFS}/etc/udhcpc/udhcpc.conf" <<'EOF'
RESOLV_CONF="/run/alpenglow/resolv.conf"
EOF

cat > "${ROOTFS}/etc/resolv.conf" <<'EOF'
nameserver 10.0.2.3
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
  "filesystem": {
    "immutable_root": true,
    "rootfs_layout": "/etc/alpenglow/filesystems/rootfs-layout.json",
    "state_mounts": "/etc/alpenglow/filesystems/state-mounts.json",
    "state_root": "/state",
    "user_home_root": "/home",
    "user_writable_scope": "home-only",
    "tmp_policy": {
      "path": "/tmp",
      "mode": "system-only"
    },
    "boot_policy": {
      "default_mode": "ram-root",
      "selection": "auto",
      "minimum_ram_mb": 3072,
      "fallback_mode": "disk-root",
      "fallback_device": "/dev/vda",
      "fallback_fstype": "ext4",
      "runtime_status": "/run/alpenglow/rootfs.env"
    }
  },
  "browser": {
    "profile_management": "system",
    "profiles_root": "/var/lib/alpenglow/browser/profiles",
    "cache_root": "/var/lib/alpenglow/browser/cache",
    "state_root": "/var/lib/alpenglow/browser/state",
    "logs_root": "/var/lib/alpenglow/browser/logs"
  },
  "generation": {
    "metadata": "/etc/alpenglow/generation.json",
    "mark_good_hook": "/usr/local/bin/alpenglow-generation-mark-good",
    "state": "/var/lib/alpenglow/system/update-state.json"
  },
  "package_manager": {
    "id": "oil",
    "mode": "system-packages",
    "binary": "/usr/local/bin/wax",
    "root": "/var/lib/alpenglow/oil",
    "bootstrap": "apk",
    "developer_mode_required": false
  },
  "plugins": [
    {
      "id": "remote-sync",
      "display_name": "Remote Sync",
      "kind": "optional-download",
      "enabled": false,
      "sync": {
        "files": false,
        "photos": false,
        "clipboard": false
      }
    }
  ]
}
EOF

cat > "${ROOTFS}/etc/alpenglow/package-manager.json" <<'EOF'
{
  "id": "oil",
  "display_name": "Oil",
  "mode": "system-packages",
  "binary": "/usr/local/bin/wax",
  "state_root": "/var/lib/alpenglow/oil",
  "bootstrap": "apk",
  "developer_mode_required": false,
  "manages": [
    "system-packages",
    "userland-packages",
    "generations",
    "manifests"
  ],
  "does_not_manage": [
    "browser-profile-vault"
  ]
}
EOF

cat > "${ROOTFS}/etc/alpenglow/plugins/remote-sync.json" <<'EOF'
{
  "id": "remote-sync",
  "display_name": "Remote Sync",
  "kind": "optional-download",
  "entrypoint": "/var/lib/alpenglow/system/plugins/remote-sync",
  "capabilities": [
    "profile-sync",
    "encrypted-relay",
    "cross-device-sync"
  ],
  "sync_features": {
    "files": false,
    "photos": false,
    "clipboard": false
  },
  "packages": [
  ]
}
EOF

cat > "${ROOTFS}/var/lib/alpenglow/system/plugin-installs.json" <<'EOF'
{
  "plugins": []
}
EOF

cp "${SERVICE_REGISTRY_SRC}" "${ROOTFS}/etc/alpenglow/services.json"
cp "${KERNEL_POLICY_SRC}" "${ROOTFS}/etc/alpenglow/kernel-policy.json"

mkdir -p "${ROOTFS}/etc/sysctl.d"
cat > "${ROOTFS}/etc/sysctl.d/99-alpenglow-internet-os.conf" <<'EOF'
net.core.somaxconn=4096
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.all.send_redirects=0
vm.swappiness=20
vm.vfs_cache_pressure=50
kernel.unprivileged_bpf_disabled=1
EOF

cat > "${ROOTFS}/etc/alpenglow/update-policy.json" <<'EOF'
{
  "strategy": "atomic-generations",
  "rollback_enabled": true,
  "channels": ["stable"],
  "generation_root": "/sysroot/alpenglow",
  "retained_generations": 2,
  "default_boot_mode": "ram-root",
  "fallback_boot_mode": "disk-root",
  "mark_good_hook": "/usr/local/bin/alpenglow-generation-mark-good",
  "interactive_mark_good": true
}
EOF

cat > "${ROOTFS}/etc/alpenglow/generation.json" <<'EOF'
{
  "id": "alpenglow-0001",
  "slot": "current",
  "status": "pending-good",
  "root_mode": "ram-root",
  "fallback_mode": "disk-root",
  "metadata_schema": 1,
  "mark_good_hook": "/usr/local/bin/alpenglow-generation-mark-good",
  "state_path": "/var/lib/alpenglow/system/update-state.json"
}
EOF

cp "${ROOTFS}/etc/alpenglow/generation.json" "${ROOTFS}/etc/alpenglow/generations/alpenglow-0001.json"

cat > "${ROOTFS}/var/lib/alpenglow/system/plugin-state.json" <<'EOF'
{
  "plugins": [
    {
      "id": "remote-sync",
      "display_name": "Remote Sync",
      "kind": "optional-download",
      "enabled": false,
      "sync": {
        "files": false,
        "photos": false,
        "clipboard": false
      }
    }
  ]
}
EOF

cat > "${ROOTFS}/var/lib/alpenglow/system/update-state.json" <<'EOF'
{
  "active_generation": "alpenglow-0001",
  "staged_generation": null,
  "rollback_generation": null,
  "boot_status": "pending-good",
  "mark_good_source": null,
  "last_result": "bootstrapped"
}
EOF

cat > "${ROOTFS}/etc/local.d/alpenglow-firstboot.start" <<'EOF'
#!/bin/sh
set -eu

chown -R alpenglow:alpenglow /var/lib/alpenglow/browser >/dev/null 2>&1 || true
chown -R sold:sold /var/lib/alpenglow/files >/dev/null 2>&1 || true
chown -R sold:sold /var/lib/alpenglow/system >/dev/null 2>&1 || true

if command -v rc-update >/dev/null 2>&1; then
  # Keep the service graph minimal for browser appliance mode.
  for svc in acpid avahi-daemon bluetooth cron cupsd hwdrivers localmount machine-id nftables syslog wpa_supplicant; do
    rc-update del "${svc}" default >/dev/null 2>&1 || true
  done
  rc-update add networking default >/dev/null 2>&1 || true
  rc-update add seatd default >/dev/null 2>&1 || true
  rc-update add alpenglow-kernel-policy default >/dev/null 2>&1 || true
  rc-update add alpenglow-zram default >/dev/null 2>&1 || true
  rc-update add alpenglow-pressure default >/dev/null 2>&1 || true
fi
EOF

chmod +x "${ROOTFS}/etc/local.d/alpenglow-firstboot.start"

# Make default runlevel explicit and minimal.
mkdir -p "${ROOTFS}/etc/runlevels/default"
find "${ROOTFS}/etc/runlevels/default" -mindepth 1 -maxdepth 1 -exec rm -f {} +
for svc in networking seatd alpenglow-kernel-policy alpenglow-zram alpenglow-pressure alpenglow-netd sold alpenglow-session; do
  if [ -f "${ROOTFS}/etc/init.d/${svc}" ]; then
    ln -sf "/etc/init.d/${svc}" "${ROOTFS}/etc/runlevels/default/${svc}"
  fi
done

echo "Configured Alpenglow Alpine rootfs at ${ROOTFS}"

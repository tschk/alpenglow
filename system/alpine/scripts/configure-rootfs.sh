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

ensure_shadow() {
  name="$1"
  if [ -f "${ROOTFS}/etc/shadow" ] && ! grep -q "^${name}:" "${ROOTFS}/etc/shadow" 2>/dev/null; then
    printf '%s:!::0:::::\n' "${name}" >>"${ROOTFS}/etc/shadow"
  fi
}

ensure_group "soliloquy" "${SOLILOQUY_GID}"
ensure_group "sold" "${SOLD_GID}"
ensure_user "soliloquy" "${SOLILOQUY_UID}" "${SOLILOQUY_GID}" "/var/lib/soliloquy"
ensure_user "sold" "${SOLD_UID}" "${SOLD_GID}" "/var/lib/soliloquy/system"
ensure_shadow "soliloquy"
ensure_shadow "sold"

mkdir -p "${ROOTFS}/etc/init.d" "${ROOTFS}/usr/local/bin"
mkdir -p "${ROOTFS}/etc/local.d"
mkdir -p "${ROOTFS}/etc/network"
mkdir -p "${ROOTFS}/etc/soliloquy/filesystems"
mkdir -p "${ROOTFS}/etc/soliloquy/plugins"
mkdir -p "${ROOTFS}/etc/soliloquy/services"
mkdir -p "${ROOTFS}/etc/soliloquy/generations"
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
  "${ROOTFS}/var/lib/soliloquy/oil"
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

mkdir -p "${ROOTFS}/tmp"
chmod 755 "${ROOTFS}/tmp"

cp -R "${OVERLAY_DIR}/." "${ROOTFS}/"
cp "${OPENRC_DIR}/seatd" "${ROOTFS}/etc/init.d/seatd"
cp "${OPENRC_DIR}/sol-kernel-policy" "${ROOTFS}/etc/init.d/sol-kernel-policy"
cp "${OPENRC_DIR}/sol-netd" "${ROOTFS}/etc/init.d/sol-netd"
cp "${OPENRC_DIR}/sol-pressure" "${ROOTFS}/etc/init.d/sol-pressure"
cp "${OPENRC_DIR}/sol-zram" "${ROOTFS}/etc/init.d/sol-zram"
cp "${OPENRC_DIR}/sol-session" "${ROOTFS}/etc/init.d/sol-session"
if [ -f "${OPENRC_DIR}/sold" ]; then
  cp "${OPENRC_DIR}/sold" "${ROOTFS}/etc/init.d/sold"
fi
cp "${BIN_SRC}/apply-kernel-policy.sh" "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh"
cp "${BIN_SRC}/apply-pressure-policy.sh" "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh"
cp "${BIN_SRC}/apply-zram-policy.sh" "${ROOTFS}/usr/local/bin/apply-zram-policy.sh"
cp "${BIN_SRC}/sol-session-start" "${ROOTFS}/usr/local/bin/sol-session-start"
cp "${BIN_SRC}/sol-servo-wrapper" "${ROOTFS}/usr/local/bin/sol-servo-wrapper"
cp "${FILESYSTEM_MANIFEST_DIR}/rootfs-layout.json" "${ROOTFS}/etc/soliloquy/filesystems/rootfs-layout.json"
cp "${FILESYSTEM_MANIFEST_DIR}/state-mounts.json" "${ROOTFS}/etc/soliloquy/filesystems/state-mounts.json"

chmod +x \
  "${ROOTFS}/etc/init.d/seatd" \
  "${ROOTFS}/etc/init.d/sol-kernel-policy" \
  "${ROOTFS}/etc/init.d/sol-netd" \
  "${ROOTFS}/etc/init.d/sol-pressure" \
  "${ROOTFS}/etc/init.d/sol-zram" \
  "${ROOTFS}/etc/init.d/sol-session" \
  "${ROOTFS}/etc/init.d/sold" \
  "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-zram-policy.sh" \
  "${ROOTFS}/usr/local/bin/soliloquy-generation-mark-good" \
  "${ROOTFS}/usr/local/bin/sol-session-start" \
  "${ROOTFS}/usr/local/bin/sol-servo-wrapper" \
  "${ROOTFS}/init"

if [ -f "${ALPINE_DIR}/packages-v0.txt" ]; then
  cp "${ALPINE_DIR}/packages-v0.txt" "${ROOTFS}/etc/apk/world.soliloquy"
fi
if [ -f "${ALPINE_DIR}/packages-v0-dev.txt" ]; then
  cp "${ALPINE_DIR}/packages-v0-dev.txt" "${ROOTFS}/etc/apk/world.soliloquy.dev"
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
RESOLV_CONF="/run/soliloquy/resolv.conf"
EOF

cat > "${ROOTFS}/etc/resolv.conf" <<'EOF'
nameserver 10.0.2.3
EOF

cat > "${ROOTFS}/etc/soliloquy/filesystems/fstab.plan" <<'EOF'
soliloquy-root / glowfs ro,nodev 0 0
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
  "filesystem": {
    "immutable_root": true,
    "rootfs_layout": "/etc/soliloquy/filesystems/rootfs-layout.json",
    "state_mounts": "/etc/soliloquy/filesystems/state-mounts.json",
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
      "runtime_status": "/run/soliloquy/rootfs.env"
    }
  },
  "browser": {
    "profile_management": "system",
    "profiles_root": "/var/lib/soliloquy/browser/profiles",
    "cache_root": "/var/lib/soliloquy/browser/cache",
    "state_root": "/var/lib/soliloquy/browser/state",
    "logs_root": "/var/lib/soliloquy/browser/logs"
  },
  "generation": {
    "metadata": "/etc/soliloquy/generation.json",
    "mark_good_hook": "/usr/local/bin/soliloquy-generation-mark-good",
    "state": "/var/lib/soliloquy/system/update-state.json"
  },
  "package_manager": {
    "id": "oil",
    "mode": "system-packages",
    "binary": "/usr/local/bin/wax",
    "root": "/var/lib/soliloquy/oil",
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

cat > "${ROOTFS}/etc/soliloquy/package-manager.json" <<'EOF'
{
  "id": "oil",
  "display_name": "Oil",
  "mode": "system-packages",
  "binary": "/usr/local/bin/wax",
  "state_root": "/var/lib/soliloquy/oil",
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

cat > "${ROOTFS}/etc/soliloquy/plugins/remote-sync.json" <<'EOF'
{
  "id": "remote-sync",
  "display_name": "Remote Sync",
  "kind": "optional-download",
  "entrypoint": "/var/lib/soliloquy/system/plugins/remote-sync",
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

cat > "${ROOTFS}/var/lib/soliloquy/system/plugin-installs.json" <<'EOF'
{
  "plugins": []
}
EOF

cp "${SERVICE_REGISTRY_SRC}" "${ROOTFS}/etc/soliloquy/services.json"
cp "${KERNEL_POLICY_SRC}" "${ROOTFS}/etc/soliloquy/kernel-policy.json"

mkdir -p "${ROOTFS}/etc/sysctl.d"
cat > "${ROOTFS}/etc/sysctl.d/99-soliloquy-internet-os.conf" <<'EOF'
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

cat > "${ROOTFS}/etc/soliloquy/update-policy.json" <<'EOF'
{
  "strategy": "atomic-generations",
  "rollback_enabled": true,
  "channels": ["stable"],
  "generation_root": "/sysroot/soliloquy",
  "retained_generations": 2,
  "default_boot_mode": "ram-root",
  "fallback_boot_mode": "disk-root",
  "mark_good_hook": "/usr/local/bin/soliloquy-generation-mark-good",
  "interactive_mark_good": true
}
EOF

cat > "${ROOTFS}/etc/soliloquy/generation.json" <<'EOF'
{
  "id": "soliloquy-0001",
  "slot": "current",
  "status": "pending-good",
  "root_mode": "ram-root",
  "fallback_mode": "disk-root",
  "metadata_schema": 1,
  "mark_good_hook": "/usr/local/bin/soliloquy-generation-mark-good",
  "state_path": "/var/lib/soliloquy/system/update-state.json"
}
EOF

cp "${ROOTFS}/etc/soliloquy/generation.json" "${ROOTFS}/etc/soliloquy/generations/soliloquy-0001.json"

cat > "${ROOTFS}/var/lib/soliloquy/system/plugin-state.json" <<'EOF'
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

cat > "${ROOTFS}/var/lib/soliloquy/system/update-state.json" <<'EOF'
{
  "active_generation": "soliloquy-0001",
  "staged_generation": null,
  "rollback_generation": null,
  "boot_status": "pending-good",
  "mark_good_source": null,
  "last_result": "bootstrapped"
}
EOF

cat > "${ROOTFS}/etc/local.d/soliloquy-firstboot.start" <<'EOF'
#!/bin/sh
set -eu

chown -R soliloquy:soliloquy /var/lib/soliloquy/browser >/dev/null 2>&1 || true
chown -R sold:sold /var/lib/soliloquy/files >/dev/null 2>&1 || true
chown -R sold:sold /var/lib/soliloquy/system >/dev/null 2>&1 || true

if command -v rc-update >/dev/null 2>&1; then
  # Keep the service graph minimal for browser appliance mode.
  for svc in acpid avahi-daemon bluetooth cron cupsd hwdrivers localmount machine-id nftables syslog wpa_supplicant; do
    rc-update del "${svc}" default >/dev/null 2>&1 || true
  done
  rc-update add networking default >/dev/null 2>&1 || true
  rc-update add seatd default >/dev/null 2>&1 || true
  rc-update add sol-kernel-policy default >/dev/null 2>&1 || true
  rc-update add sol-zram default >/dev/null 2>&1 || true
  rc-update add sol-pressure default >/dev/null 2>&1 || true
fi
EOF

chmod +x "${ROOTFS}/etc/local.d/soliloquy-firstboot.start"

# Make default runlevel explicit and minimal.
mkdir -p "${ROOTFS}/etc/runlevels/default"
find "${ROOTFS}/etc/runlevels/default" -mindepth 1 -maxdepth 1 -exec rm -f {} +
for svc in networking seatd sol-kernel-policy sol-zram sol-pressure sol-netd sold sol-session; do
  if [ -f "${ROOTFS}/etc/init.d/${svc}" ]; then
    ln -sf "/etc/init.d/${svc}" "${ROOTFS}/etc/runlevels/default/${svc}"
  fi
done

echo "Configured Soliloquy Alpine rootfs at ${ROOTFS}"

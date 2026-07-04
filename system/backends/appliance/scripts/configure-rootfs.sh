#!/bin/sh
# Alpenglow native appliance — configure-rootfs
# Builds the rootfs directory for the unified appliance target.
set -eu

ROOTFS="${1:-}"
if [ -z "${ROOTFS}" ]; then
  echo "usage: $0 <rootfs-dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
BACKEND_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${BACKEND_DIR}/../../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
OVERLAY_DIR="${BACKEND_DIR}/rootfs-overlay"
FILESYSTEM_MANIFEST_DIR="${ROOT_DIR}/system/appliance/filesystems"
BIN_SRC="${BACKEND_DIR}/scripts"
ALPENGLOW_UID="770"
ALPENGLOW_GID="770"
SOLD_UID="771"
SOLD_GID="771"
SEATD_UID="772"
SEATD_GID="772"
IWD_UID="773"
IWD_GID="773"
PIPEWIRE_UID="774"
PIPEWIRE_GID="774"
DROPBEAR_UID="775"
DROPBEAR_GID="775"
CHRONY_UID="776"
CHRONY_GID="776"
DNSMASQ_UID="777"
DNSMASQ_GID="777"

if [ ! -d "${ROOTFS}" ]; then
  echo "rootfs directory not found: ${ROOTFS}" >&2
  exit 1
fi

# ── usrmerge: canonicalize /bin, /sbin, /lib, /lib64 under /usr ─────
# Oil (Phase 1 of build-rootfs.sh) already populated the rootfs before
# this script runs, so /bin, /sbin, /lib, /lib64 may already hold real
# files. Move whatever is there into the usr-prefixed real directory,
# then replace the legacy top-level path with a symlink so nothing that
# still hardcodes the old path breaks.
mkdir -p "${ROOTFS}/usr/bin" "${ROOTFS}/usr/sbin" "${ROOTFS}/usr/lib" "${ROOTFS}/usr/lib64"
for d in bin sbin lib lib64; do
  if [ -d "${ROOTFS}/${d}" ] && [ ! -L "${ROOTFS}/${d}" ]; then
    cp -R "${ROOTFS}/${d}/." "${ROOTFS}/usr/${d}/" 2>/dev/null || true
    rm -rf "${ROOTFS}/${d}"
  fi
  [ -e "${ROOTFS}/${d}" ] || ln -s "usr/${d}" "${ROOTFS}/${d}"
done

ensure_group() { name="$1"; gid="$2"
  if ! grep -q "^${name}:" "${ROOTFS}/etc/group" 2>/dev/null; then
    printf '%s:x:%s:\n' "${name}" "${gid}" >>"${ROOTFS}/etc/group"
  fi
}
ensure_user() { name="$1"; uid="$2"; gid="$3"; home="$4"
  if ! grep -q "^${name}:" "${ROOTFS}/etc/passwd" 2>/dev/null; then
    printf '%s:x:%s:%s:%s:%s:/usr/sbin/nologin\n' "${name}" "${uid}" "${gid}" "${name}" "${home}" >>"${ROOTFS}/etc/passwd"
  fi
}

ensure_group "alpenglow" "${ALPENGLOW_GID}"
# sold group moved to soliloquy
ensure_group "seatd" "${SEATD_GID}"
ensure_group "iwd" "${IWD_GID}"
ensure_group "pipewire" "${PIPEWIRE_GID}"
ensure_group "audio" 777
ensure_group "video" 778
ensure_group "input" 779
ensure_user "alpenglow" "${ALPENGLOW_UID}" "${ALPENGLOW_GID}" "/var/lib/alpenglow"

ensure_user "seatd" "${SEATD_UID}" "${SEATD_GID}" "/var/empty"
ensure_user "iwd" "${IWD_UID}" "${IWD_GID}" "/var/empty"
ensure_group "dropbear" "${DROPBEAR_GID}"
ensure_user "dropbear" "${DROPBEAR_UID}" "${DROPBEAR_GID}" "/var/empty"
ensure_group "chrony" "${CHRONY_GID}"
ensure_user "chrony" "${CHRONY_UID}" "${CHRONY_GID}" "/var/empty"
ensure_group "dnsmasq" "${DNSMASQ_GID}"
ensure_user "dnsmasq" "${DNSMASQ_UID}" "${DNSMASQ_GID}" "/var/empty"

# Directory structure
mkdir -p "${ROOTFS}/etc/alpenglow/filesystems"
mkdir -p "${ROOTFS}/etc/alpenglow/services"
mkdir -p "${ROOTFS}/etc/alpenglow/generations"
mkdir -p "${ROOTFS}/etc/dinit.d"
mkdir -p "${ROOTFS}/usr/local/bin"
mkdir -p "${ROOTFS}/home" "${ROOTFS}/state" "${ROOTFS}/sysroot/alpenglow"
mkdir -p "${ROOTFS}/var/lib/alpenglow/oil"
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

# Dropbear SSH — host key directory
mkdir -p "${ROOTFS}/etc/dropbear"
chmod 755 "${ROOTFS}/etc/dropbear"

# Chrony config dir
mkdir -p "${ROOTFS}/etc/chrony"

# Dnsmasq config dir
mkdir -p "${ROOTFS}/etc/dnsmasq.d"

chmod 700 "${ROOTFS}/var/lib/alpenglow/browser/profiles" \
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
chown -R "${ALPENGLOW_UID}:${ALPENGLOW_GID}" "${ROOTFS}/var/lib/alpenglow/browser" 2>/dev/null || true
chown -R "${SOLD_UID}:${SOLD_GID}" "${ROOTFS}/var/lib/alpenglow/files" "${ROOTFS}/var/lib/alpenglow/system" 2>/dev/null || true

# Enable dinit boot services (profile-aware)
BUILD_PROFILE="${BUILD_PROFILE:-standard}"
case "${BUILD_PROFILE}" in
  minimal)
    BOOT_SERVICES="glowfs-mount state-mount networking earlyoom dropbear chronyd syslogd crond dnsmasq"
    WORLD_FILE="${BACKEND_DIR}/packages-minimal.txt"
    ;;
  standard)
    BOOT_SERVICES="glowfs-mount state-mount alpenglow-kernel-policy alpenglow-netd alpenglow-zram alpenglow-pressure alpenglow-power networking earlyoom dropbear chronyd syslogd crond dnsmasq"
    WORLD_FILE="${BACKEND_DIR}/packages-standard.txt"
    ;;
  desktop)
    BOOT_SERVICES="glowfs-mount state-mount seatd alpenglow-kernel-policy alpenglow-netd alpenglow-zram alpenglow-pressure alpenglow-power networking earlyoom iwd dropbear chronyd syslogd crond dnsmasq pipewire wireplumber greetd velox alpenglowed foot"
    WORLD_FILE="${BACKEND_DIR}/packages-runtime.txt"
    ;;
  *)
    echo "Unknown profile: ${BUILD_PROFILE}. Use minimal, standard, or desktop." >&2
    exit 1
    ;;
esac

# Compiler track: LLVM remains the default C/C++ toolchain; Inauguration is
# available as an alternative codegen track for .in / Rust-shaped sources.
COMPILER="${COMPILER:-llvm}"
case "${COMPILER}" in
  llvm|inauguration) ;;
  *) echo "Unknown compiler: ${COMPILER}. Use llvm or inauguration." >&2; exit 1 ;;
esac

# Copy overlay files and scripts
cp -R "${OVERLAY_DIR}/." "${ROOTFS}/"
cp "${BIN_SRC}/alpenglow-session-start" "${ROOTFS}/usr/local/bin/"
cp "${SCRIPT_DIR}/mount-glowfs-root.sh" "${ROOTFS}/usr/local/bin/"
cp "${SCRIPT_DIR}/mount-state.sh" "${ROOTFS}/usr/local/bin/"
cp "${FILESYSTEM_MANIFEST_DIR}/rootfs-layout.json" "${ROOTFS}/etc/alpenglow/filesystems/"
cp "${FILESYSTEM_MANIFEST_DIR}/state-mounts.json" "${ROOTFS}/etc/alpenglow/filesystems/"
cp "${BACKEND_DIR}/backend.json" "${ROOTFS}/etc/alpenglow/backend.json"
cp "${WORLD_FILE}" "${ROOTFS}/etc/alpenglow/world"
cp -R "${BACKEND_DIR}/dinit/." "${ROOTFS}/etc/dinit.d/"
rm -rf "${ROOTFS}/etc/runit" "${ROOTFS}/etc/sv" "${ROOTFS}/etc/apk"

mkdir -p "${ROOTFS}/etc/dinit.d/boot.d"
for service in ${BOOT_SERVICES}; do
  ln -sf "/etc/dinit.d/${service}" "${ROOTFS}/etc/dinit.d/boot.d/${service}" 2>/dev/null || true
done
{
  echo "type = scripted"
  echo "command = /usr/bin/true"
  echo "restart = no"
  for service in ${BOOT_SERVICES}; do
    echo "depends-on = ${service}"
  done
} > "${ROOTFS}/etc/dinit.d/boot"

# Compiler profile: LLVM remains the C/C++ toolchain; Inauguration is the
# alternate codegen track for .in / Rust-shaped sources.
mkdir -p "${ROOTFS}/etc/profile.d" "${ROOTFS}/etc/sysctl.d"
if [ "${COMPILER}" = "inauguration" ]; then
  cat > "${ROOTFS}/etc/profile.d/alpenglow-compiler.sh" <<'COMPEOF'
# Alpenglow system compiler: Inauguration track (LLVM still handles C/C++).
ALPENGLOW_COMPILER=inauguration
IN=/usr/local/bin/in
IN_TARGET=x86_64-unknown-linux-gnu
CC=clang
CXX=clang++
LD=lld
AR=llvm-ar
NM=llvm-nm
OBJCOPY=llvm-objcopy
RANLIB=llvm-ranlib
CFLAGS="-O2 -pipe -fomit-frame-pointer -fstack-protector-strong"
CXXFLAGS="-O2 -pipe -fomit-frame-pointer -fstack-protector-strong"
LDFLAGS="-fuse-ld=lld -Wl,-z,relro,-z,now"
export ALPENGLOW_COMPILER IN IN_TARGET CC CXX LD AR NM OBJCOPY RANLIB CFLAGS CXXFLAGS LDFLAGS
COMPEOF
else
  cat > "${ROOTFS}/etc/profile.d/alpenglow-compiler.sh" <<'COMPEOF'
# Alpenglow system compiler: LLVM/Clang (default)
# Inauguration is available as an alternate codegen track.
ALPENGLOW_COMPILER=llvm
CC=clang
CXX=clang++
LD=lld
AR=llvm-ar
NM=llvm-nm
OBJCOPY=llvm-objcopy
RANLIB=llvm-ranlib
CFLAGS="-O2 -pipe -fomit-frame-pointer -fstack-protector-strong"
CXXFLAGS="-O2 -pipe -fomit-frame-pointer -fstack-protector-strong"
LDFLAGS="-fuse-ld=lld -Wl,-z,relro,-z,now"
export ALPENGLOW_COMPILER CC CXX LD AR NM OBJCOPY RANLIB CFLAGS CXXFLAGS LDFLAGS
COMPEOF
fi
chmod 644 "${ROOTFS}/etc/profile.d/alpenglow-compiler.sh"

# Default shell
if [ ! -f "${ROOTFS}/usr/bin/sh" ]; then
  ln -s /usr/bin/oksh "${ROOTFS}/usr/bin/sh" 2>/dev/null || true
fi

# Hardened sysctl defaults
cat > "${ROOTFS}/etc/sysctl.d/99-hardened.conf" <<'SYSCTL'
# Kernel hardening
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.printk=3 3 3 3
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.tcp_rfc1337=1
vm.unprivileged_userfaultfd=0
SYSCTL

chmod +x "${ROOTFS}/usr/local/bin/"*.sh
chmod +x "${ROOTFS}/opt/alpenglow/session-init" 2>/dev/null || true
chmod +x "${ROOTFS}/init" 2>/dev/null || true
find "${ROOTFS}/etc/dinit.d" -type f -exec chmod +x {} \; 2>/dev/null || true

cat > "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh" <<'KERNELPOLICY'
#!/bin/sh
set -eu

set_sysctl() {
  key="$1"
  value="$2"
  path="/proc/sys/$(printf '%s' "${key}" | tr . /)"
  [ -w "${path}" ] || return 0
  printf '%s\n' "${value}" >"${path}" 2>/dev/null || true
}

set_sysctl kernel.kptr_restrict 2
set_sysctl kernel.dmesg_restrict 1
set_sysctl kernel.unprivileged_bpf_disabled 1
set_sysctl net.core.bpf_jit_harden 2
set_sysctl net.ipv4.tcp_syncookies 1
set_sysctl net.ipv4.conf.all.rp_filter 1
set_sysctl net.ipv4.conf.default.rp_filter 1
set_sysctl net.ipv4.tcp_rfc1337 1
set_sysctl vm.unprivileged_userfaultfd 0
KERNELPOLICY

cat > "${ROOTFS}/usr/local/bin/apply-zram-policy.sh" <<'ZRAMPOLICY'
#!/bin/sh
set -eu

if [ -d /sys/class/zram-control ] && [ ! -e /dev/zram0 ]; then
  cat /sys/class/zram-control/hot_add >/dev/null 2>&1 || true
fi

if [ -e /sys/block/zram0/disksize ]; then
  mem_kb=$(awk '/MemTotal:/ { print $2 }' /proc/meminfo 2>/dev/null || printf '0')
  if [ "${mem_kb}" -gt 0 ]; then
    size_kb=$((mem_kb / 2))
    printf '%sK\n' "${size_kb}" >/sys/block/zram0/disksize 2>/dev/null || true
  fi
fi

if [ -e /dev/zram0 ] && command -v mkswap >/dev/null 2>&1 && command -v swapon >/dev/null 2>&1; then
  mkswap /dev/zram0 >/dev/null 2>&1 || true
  swapon /dev/zram0 >/dev/null 2>&1 || true
fi
ZRAMPOLICY

cat > "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh" <<'PRESSUREPOLICY'
#!/bin/sh
set -eu

while :; do
  sleep 60
done
PRESSUREPOLICY
chmod 755 \
  "${ROOTFS}/usr/local/bin/apply-kernel-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-zram-policy.sh" \
  "${ROOTFS}/usr/local/bin/apply-pressure-policy.sh"

# System configuration
case "${COMPILER}" in
  inauguration)
    COMPILER_DEFAULT="inauguration"
    COMPILER_POLICY="inauguration-primary"
    ;;
  *)
    COMPILER_DEFAULT="clang"
    COMPILER_POLICY="llvm-primary"
    ;;
esac
case "${BUILD_PROFILE}" in
  desktop)
    DISPLAY_JSON='{"server":"wayland","compositor":"velox","session_manager":"greetd","terminal":"foot","infrastructure":"seatd","shell":"alpenglowed"}'
    AUDIO_JSON='{"server":"pipewire","session_manager":"wireplumber","backend":"alsa"}'
    NETWORKING_JSON='{"dhcp":"sdhcp","wifi":"iwd"}'
    POWER_JSON='{"manager":"elogind","script":"/usr/local/bin/alpenglow-power.sh"}'
    KERNEL_TYPE="desktop-appliance"
    KERNEL_FEATURES='["rust","sound","wireless","acpi","usb-hid"]'
    ESSENTIAL_SERVICES='["mount-filesystems","state-mount","elogind","seatd","networking"]'
    SYSTEM_SERVICES='["alpenglow-kernel-policy","alpenglow-zram","alpenglow-pressure","alpenglow-netd","alpenglow-power","iwd","syslogd","crond"]'
    SESSION_SERVICES='["pipewire","wireplumber","greetd","velox","alpenglowed","foot"]'
    USER_INIT='["alpenglow-session"]'
    ;;
  standard)
    DISPLAY_JSON='null'
    AUDIO_JSON='null'
    NETWORKING_JSON='{"dhcp":"sdhcp"}'
    POWER_JSON='{"script":"/usr/local/bin/alpenglow-power.sh"}'
    KERNEL_TYPE="standard-appliance"
    KERNEL_FEATURES='["rust","acpi"]'
    ESSENTIAL_SERVICES='["mount-filesystems","state-mount","networking"]'
    SYSTEM_SERVICES='["alpenglow-kernel-policy","alpenglow-zram","alpenglow-pressure","alpenglow-netd","alpenglow-power","syslogd","crond"]'
    SESSION_SERVICES='[]'
    USER_INIT='[]'
    ;;
  *)
    DISPLAY_JSON='null'
    AUDIO_JSON='null'
    NETWORKING_JSON='{"dhcp":"sdhcp"}'
    POWER_JSON='null'
    KERNEL_TYPE="minimal-appliance"
    KERNEL_FEATURES='["rust"]'
    ESSENTIAL_SERVICES='["mount-filesystems","state-mount","networking"]'
    SYSTEM_SERVICES='["syslogd","crond"]'
    SESSION_SERVICES='[]'
    USER_INIT='[]'
    ;;
esac
cat > "${ROOTFS}/etc/alpenglow/system.json" <<EOF
{
  "backend": "alpenglow-native",
  "profile": "${BUILD_PROFILE}",
  "composition_model": "oasis-static",
  "boot_model": "diskless",
  "hardened": true,
  "compiler": {
    "default": "${COMPILER_DEFAULT}",
    "linker": "lld",
    "policy": "${COMPILER_POLICY}",
    "tracks": ["llvm", "inauguration"]
  },
  "filesystem": {
    "immutable_root": true,
    "diskless": true,
    "root_fs": "glowfs",
    "rootfs_layout": "/etc/alpenglow/filesystems/rootfs-layout.json",
    "state_mounts": "/etc/alpenglow/filesystems/state-mounts.json",
    "state_root": "/state"
  },
  "service_manager": {
    "id": "dinit",
    "dinit_dir": "/etc/dinit.d",
    "boot_dir": "/etc/dinit.d/boot.d"
  },
  "package_manager": {
    "id": "oil",
    "mode": "native",
    "binary": "/usr/local/bin/wax",
    "state_root": "/var/lib/alpenglow/oil",
    "bootstrap": "oil",
    "runtime_mutation": false
  },
  "display": ${DISPLAY_JSON},
  "audio": ${AUDIO_JSON},
  "networking": ${NETWORKING_JSON},
  "power": ${POWER_JSON},
  "kernel": {
    "policy": "hardened",
    "type": "${KERNEL_TYPE}",
    "features": ${KERNEL_FEATURES}
  },
  "userland": {
    "core": "toybox",
    "style": "minimal",
    "shell": "oksh",
    "crypto": "bearssl"
  },
  "services": {
    "essential": ${ESSENTIAL_SERVICES},
    "system": ${SYSTEM_SERVICES},
    "session": ${SESSION_SERVICES},
    "network_services": ["dropbear", "chronyd", "dnsmasq"],
    "user_init": ${USER_INIT}
  }
}
EOF

# ── Early boot setup: /etc/hosts + /etc/resolv.conf ───────────────
cat > "${ROOTFS}/etc/hosts" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 alpenglow
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
HOSTS
chmod 644 "${ROOTFS}/etc/hosts"

# ── SSH: dropbear config ────────────────────────────────────────────
# Host keys auto-generated on first start; no config file needed.
# Authorized keys directory for root
mkdir -p "${ROOTFS}/root/.ssh"
chmod 700 "${ROOTFS}/root/.ssh"

# ── NTP: chrony config ─────────────────────────────────────────────
cat > "${ROOTFS}/etc/chrony/chrony.conf" <<'CHRONY'
# Chrony NTP configuration
pool pool.ntp.org iburst
makestep 1.0 3
rtcsync
cmdport 0
bindcmdaddress 127.0.0.1
bindcmdaddress ::1
CHRONY
chmod 644 "${ROOTFS}/etc/chrony/chrony.conf"

# ── DNS: dnsmasq config ────────────────────────────────────────────
cat > "${ROOTFS}/etc/dnsmasq.conf" <<'DNSMASQ'
# Dnsmasq: local DNS caching resolver
port=53
domain-needed
bogus-priv
no-resolv
no-poll
server=1.1.1.1
server=8.8.8.8
cache-size=1000
DNSMASQ
chmod 644 "${ROOTFS}/etc/dnsmasq.conf"

# ── Editor: install vro ────────────────────────────────────────────
VRO_SRC="${BACKEND_DIR}/vro/vro"
if [ -f "${VRO_SRC}" ]; then
  cp "${VRO_SRC}" "${ROOTFS}/usr/local/bin/vro"
  chmod 755 "${ROOTFS}/usr/local/bin/vro"
  ln -sf /usr/local/bin/vro "${ROOTFS}/usr/local/bin/vi" 2>/dev/null || true
fi

# ── User management basics ──────────────────────────────────────────
# toybox passwd enabled; root password managed via chpasswd on state
mkdir -p "${ROOTFS}/etc/crontabs"
cat > "${ROOTFS}/etc/crontabs/root" <<'CRONTAB'
# Root cron jobs
0 0 * * * /usr/local/bin/logrotate.sh >/dev/null 2>&1
CRONTAB
chmod 600 "${ROOTFS}/etc/crontabs/root"

# ── Rotate logs daily ──────────────────────────────────────────────
cat > "${ROOTFS}/usr/local/bin/logrotate.sh" <<'LOGX'
#!/usr/bin/toybox sh
# Advanced log rotation script
MAX_LOGS=7
for log in /var/log/alpenglow/*.log; do
  [ -f "${log}" ] || continue
  rm -f "${log}.${MAX_LOGS}" 2>/dev/null || true
  i=${MAX_LOGS}
  while [ "$i" -gt 1 ]; do
    prev=$((i - 1))
    [ -f "${log}.${prev}" ] && mv "${log}.${prev}" "${log}.${i}" 2>/dev/null || true
    i=${prev}
  done
  mv "${log}" "${log}.1" 2>/dev/null || true
done
LOGX
chmod 755 "${ROOTFS}/usr/local/bin/logrotate.sh"

printf 'Configured Alpenglow native appliance rootfs at %s\n' "${ROOTFS}"

#!/bin/sh
# Shared rootfs assembly for boot-native.sh.
# FAST/minimal: lean toybox dinit units. standard/desktop: configure-rootfs.sh + QEMU serial.
# Expects ROOTFS_DIR, OUT_DIR, ROOT_DIR, BACKEND_DIR, BUILD_PROFILE, FAST, and toybox_has.
set -eu

_assemble_qemu_mount_units() {
  mkdir -p "${ROOTFS_DIR}/etc/dinit.d"
  cat > "${ROOTFS_DIR}/etc/dinit.d/shell-ttyS0" << 'SHELL'
type = process
command = /bin/toybox getty -L 115200 ttyS0 vt100
restart = yes
depends-on = mount-filesystems
SHELL

  cat > "${ROOTFS_DIR}/etc/dinit.d/mount-filesystems" << 'MOUNT'
type = scripted
command = /bin/toybox sh -c "/bin/toybox mount -t proc proc /proc; /bin/toybox mount -t sysfs sysfs /sys; /bin/toybox mount -t devtmpfs devtmpfs /dev; /bin/toybox mount -t tmpfs -o nosuid,nodev,mode=0755 tmpfs /run"
restart = no
MOUNT
}

_assemble_minimal_toybox_networking() {
  cat > "${ROOTFS_DIR}/etc/dinit.d/networking" << 'NET'
type = scripted
command = /bin/toybox udhcpc -i eth0 -s /bin/toybox -q
restart = yes
depends-on = mount-filesystems
NET
}

_assemble_minimal_toybox_syslogd() {
  cat > "${ROOTFS_DIR}/etc/dinit.d/syslogd" << 'SYSLOG'
type = process
command = /bin/toybox syslogd -n
restart = yes
depends-on = mount-filesystems
SYSLOG
}

_assemble_minimal_toybox_crond() {
  cat > "${ROOTFS_DIR}/etc/dinit.d/crond" << 'CROND'
type = process
command = /bin/toybox crond -n
restart = yes
depends-on = syslogd
CROND
}

_assemble_boot_native_passwd() {
  mkdir -p "${ROOTFS_DIR}/etc"
  cat > "${ROOTFS_DIR}/etc/passwd" << 'PASSWD'
root:x:0:0:root:/root:/bin/toybox sh
seatd:x:772:772:seatd:/var/empty:/sbin/nologin
PASSWD
  cat > "${ROOTFS_DIR}/etc/shadow" << 'SHADOW'
root::19999:0:99999:7:::
SHADOW
  cat > "${ROOTFS_DIR}/etc/group" << 'GROUP'
root:x:0:
wheel:x:10:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
news:x:9:
uucp:x:10:
man:x:12:
proxy:x:13:
kmem:x:15:
dialout:x:20:
fax:x:21:
voice:x:22:
cdrom:x:24:
floppy:x:25:
tape:x:26:
sudo:x:27:
audio:x:29:pipewire
video:x:44:seatd
input:x:777:
seatd:x:772:
iwd:x:773:
pipewire:x:774:
GROUP
}

_assemble_common_rootfs_tail() {
  mkdir -p "${ROOTFS_DIR}/usr/share/udhcpc"
  cat > "${ROOTFS_DIR}/usr/share/udhcpc/default.script" << 'SCRIPT'
#!/bin/toybox sh
case "$1" in
  bound|renew) /sbin/ifconfig $interface $ip netmask $subnet; route add default gw $router 2>/dev/null;;
  deconfig) /sbin/ifconfig $interface 0.0.0.0;;
esac
SCRIPT
  chmod 755 "${ROOTFS_DIR}/usr/share/udhcpc/default.script"

  mkdir -p "${ROOTFS_DIR}/root"
  mkdir -p "${ROOTFS_DIR}/lib/modules"
  if [ -f "${ALPENGLOW_MODULE}" ]; then
    cp "${ALPENGLOW_MODULE}" "${ROOTFS_DIR}/lib/modules/"
  fi

  if [ "${ZIG_INIT:-0}" = "1" ] && [ -f "${OUT_DIR}/alpenglow-init" ]; then
    cp "${OUT_DIR}/alpenglow-init" "${ROOTFS_DIR}/init"
    chmod 755 "${ROOTFS_DIR}/init"
  else
    cat > "${ROOTFS_DIR}/init" << 'INIT'
#!/bin/toybox sh
/bin/toybox mount -t proc proc /proc
/bin/toybox mount -t sysfs sysfs /sys
/bin/toybox mount -t devtmpfs devtmpfs /dev
exec </dev/ttyS0 >/dev/ttyS0 2>&1
/bin/toybox mount -t tmpfs -o nosuid,nodev,mode=0755 tmpfs /run
/bin/toybox mkdir -p /dev/shm /tmp 2>/dev/null
/bin/toybox chmod 01777 /dev/shm /tmp
SHM_SIZE="mode=1777,size=256m"
if [ -r /proc/meminfo ]; then
  mem_total_kb=""
  while read -r key value _; do
    [ "$key" = "MemTotal:" ] && { mem_total_kb="$value"; break; }
  done < /proc/meminfo
  if [ -n "$mem_total_kb" ]; then
    SHM_SIZE="mode=1777,size=$((mem_total_kb / 2))k"
  fi
fi
/bin/toybox mount -t tmpfs -o nosuid,nodev,"$SHM_SIZE" tmpfs /dev/shm
/bin/toybox mount -t tmpfs -o nosuid,nodev,mode=1777 tmpfs /tmp
/bin/toybox mkdir -p /run/user/0
/bin/toybox chown 0:0 /run/user/0
/bin/toybox chmod 700 /run/user/0
/bin/toybox mkdir -p /state
# Try to mount state partition (if available)
state_dev=""
for arg in $(cat /proc/cmdline); do
  case "$arg" in
    alpenglow.state=LABEL=*) state_dev="/dev/disk/by-label/${arg#alpenglow.state=LABEL=}" ;;
    alpenglow.state=*) state_dev="${arg#alpenglow.state=}" ;;
  esac
done
if [ -z "$state_dev" ]; then
  state_dev="/dev/disk/by-label/alpenglow-state"
fi
if [ -b "$state_dev" ]; then
  /bin/toybox mount -t bcachefs -o rw,nosuid,nodev "$state_dev" /state 2>/dev/null && echo "Mounted state: $state_dev"
fi
echo ""
echo "Alpenglow boot"
echo ""
# Log memory at boot for benchmark
if [ -f /proc/meminfo ]; then
  /bin/toybox grep -E 'MemTotal|MemFree' /proc/meminfo 2>/dev/null
fi
exec /sbin/dinit -d /etc/dinit.d -s -t boot
INIT
    chmod 755 "${ROOTFS_DIR}/init"
  fi

  mknod -m 622 "${ROOTFS_DIR}/dev/console" c 5 1 2>/dev/null || true
  mknod -m 666 "${ROOTFS_DIR}/dev/null" c 1 3 2>/dev/null || true
  mknod -m 666 "${ROOTFS_DIR}/dev/zero" c 1 5 2>/dev/null || true
  mknod -m 444 "${ROOTFS_DIR}/dev/random" c 1 8 2>/dev/null || true
  mknod -m 444 "${ROOTFS_DIR}/dev/urandom" c 1 9 2>/dev/null || true

  echo "alpenglow" > "${ROOTFS_DIR}/etc/hostname"

  mkdir -p "${ROOTFS_DIR}/root/.ssh"
  chmod 700 "${ROOTFS_DIR}/root/.ssh"
}

_assemble_minimal_configs() {
  _assemble_boot_native_passwd

  cat > "${ROOTFS_DIR}/etc/hosts" << 'HOSTS'
127.0.0.1 localhost
127.0.1.1 alpenglow
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
HOSTS

  mkdir -p "${ROOTFS_DIR}/etc/chrony"
  cat > "${ROOTFS_DIR}/etc/chrony/chrony.conf" << 'CHRONY'
pool pool.ntp.org iburst
makestep 1.0 3
rtcsync
cmdport 0
bindcmdaddress 127.0.0.1
bindcmdaddress ::1
CHRONY

  cat > "${ROOTFS_DIR}/etc/dnsmasq.conf" << 'DNSMASQ'
listen-address=127.0.0.1
bind-interfaces
port=53
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8
cache-size=1000
DNSMASQ

  mkdir -p "${ROOTFS_DIR}/etc/crontabs"
  cat > "${ROOTFS_DIR}/etc/crontabs/root" << 'CRONT'
0 0 * * * /usr/local/bin/logrotate.sh >/dev/null 2>&1
CRONT
  chmod 600 "${ROOTFS_DIR}/etc/crontabs/root"

  cat > "${ROOTFS_DIR}/usr/local/bin/logrotate.sh" << 'LOGX'
#!/bin/toybox sh
for log in /var/log/alpenglow/*.log; do
  [ -f "${log}" ] || continue
  mv "${log}" "${log}.old" 2>/dev/null || true
done
LOGX
  chmod 755 "${ROOTFS_DIR}/usr/local/bin/logrotate.sh"
}

_wire_boot_services() {
  mkdir -p "${ROOTFS_DIR}/etc/dinit.d/boot.d"
  for svc in ${BOOT_SERVICES}; do
    ln -sf "/etc/dinit.d/${svc}" "${ROOTFS_DIR}/etc/dinit.d/boot.d/${svc}" 2>/dev/null || true
  done
  {
    echo "type = scripted"
    echo "command = /bin/true"
    echo "restart = no"
    for svc in ${BOOT_SERVICES}; do
      echo "depends-on = ${svc}"
    done
  } > "${ROOTFS_DIR}/etc/dinit.d/boot"
}

_assemble_native_boot_services() {
  case "${BUILD_PROFILE}" in
    minimal)
      BOOT_SERVICES="shell-ttyS0 mount-filesystems"
      ;;
    standard)
      BOOT_SERVICES="shell-ttyS0 mount-filesystems networking syslogd crond"
      toybox_has udhcpc || BOOT_SERVICES="$(printf '%s\n' "${BOOT_SERVICES}" | sed 's/ networking//')"
      toybox_has syslogd || BOOT_SERVICES="$(printf '%s\n' "${BOOT_SERVICES}" | sed 's/ syslogd//')"
      toybox_has crond || BOOT_SERVICES="$(printf '%s\n' "${BOOT_SERVICES}" | sed 's/ crond//')"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-kernelctl" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-kernel-policy"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-netd" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-netd"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-zramctl-zig" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-zram"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-pressurectl-zig" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-pressure"
      [ -f "${ROOTFS_DIR}/usr/bin/dropbear" ] && BOOT_SERVICES="${BOOT_SERVICES} dropbear"
      [ -f "${ROOTFS_DIR}/usr/sbin/chronyd" ] && BOOT_SERVICES="${BOOT_SERVICES} chronyd"
      [ -f "${ROOTFS_DIR}/usr/sbin/dnsmasq" ] && BOOT_SERVICES="${BOOT_SERVICES} dnsmasq"
      ;;
    desktop)
      BOOT_SERVICES="shell-ttyS0 mount-filesystems"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-kernelctl" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-kernel-policy"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-netd" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-netd"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-zramctl-zig" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-zram"
      [ -f "${ROOTFS_DIR}/usr/local/bin/alpenglow-pressurectl-zig" ] && BOOT_SERVICES="${BOOT_SERVICES} alpenglow-pressure"
      if [ "${ALPENGLOW_DESKTOP_FULL}" = "1" ] && [ -f "${ROOTFS_DIR}/usr/bin/greetd" ]; then
        BOOT_SERVICES="${BOOT_SERVICES} greetd"
      elif [ -f "${ROOTFS_DIR}/usr/bin/alpenglowed-bin" ]; then
        BOOT_SERVICES="${BOOT_SERVICES} alpenglowed"
      fi
      ;;
  esac
}

_assemble_qemu_serial_login() {
  _assemble_qemu_mount_units
  ln -sf "/etc/dinit.d/shell-ttyS0" "${ROOTFS_DIR}/etc/dinit.d/boot.d/shell-ttyS0" 2>/dev/null || true
  if ! grep -q 'depends-on = shell-ttyS0' "${ROOTFS_DIR}/etc/dinit.d/boot" 2>/dev/null; then
    printf 'depends-on = shell-ttyS0\n' >> "${ROOTFS_DIR}/etc/dinit.d/boot"
  fi
  if ! grep -q '^root:' "${ROOTFS_DIR}/etc/passwd" 2>/dev/null; then
    _assemble_boot_native_passwd
  elif ! grep -q '/bin/toybox sh' "${ROOTFS_DIR}/etc/passwd" 2>/dev/null; then
    sed -i 's/^root:.*$/root:x:0:0:root:/root:/bin/toybox sh/' "${ROOTFS_DIR}/etc/passwd" 2>/dev/null || true
  fi
}

_assemble_minimal_rootfs() {
  _assemble_qemu_mount_units
  if [ "${FAST:-0}" = "1" ]; then
    BOOT_SERVICES="shell-ttyS0 mount-filesystems"
    _wire_boot_services
    _assemble_boot_native_passwd
    _assemble_common_rootfs_tail
    return
  fi
  _assemble_minimal_toybox_networking
  _assemble_minimal_toybox_syslogd
  _assemble_minimal_toybox_crond
  _assemble_native_boot_services
  _wire_boot_services
  _assemble_minimal_configs
  _assemble_common_rootfs_tail
}

_assemble_production_rootfs() {
  BUILD_PROFILE="${BUILD_PROFILE}" \
    ALPENGLOW_DESKTOP_FULL="${ALPENGLOW_DESKTOP_FULL:-1}" \
    sh "${BACKEND_DIR}/scripts/configure-rootfs.sh" "${ROOTFS_DIR}"

  _assemble_qemu_serial_login

  if [ ! -f "${ROOTFS_DIR}/etc/dinit.d/mount-filesystems" ]; then
    _assemble_qemu_mount_units
    ln -sf "/etc/dinit.d/mount-filesystems" "${ROOTFS_DIR}/etc/dinit.d/boot.d/mount-filesystems" 2>/dev/null || true
    if ! grep -q 'depends-on = mount-filesystems' "${ROOTFS_DIR}/etc/dinit.d/boot" 2>/dev/null; then
      printf 'depends-on = mount-filesystems\n' >> "${ROOTFS_DIR}/etc/dinit.d/boot"
    fi
  fi

  if [ "${BUILD_PROFILE}" = "standard" ] && ! [ -f "${ROOTFS_DIR}/usr/sbin/sdhcp" ]; then
    if toybox_has udhcpc; then
      _assemble_minimal_toybox_networking
    fi
  fi

  if [ "${BUILD_PROFILE}" = "standard" ] && toybox_has syslogd && ! [ -f "${ROOTFS_DIR}/usr/sbin/syslogd" ]; then
    _assemble_minimal_toybox_syslogd
  fi

  if [ "${BUILD_PROFILE}" = "standard" ] && toybox_has crond && ! [ -f "${ROOTFS_DIR}/usr/sbin/crond" ]; then
    _assemble_minimal_toybox_crond
  fi

  _assemble_common_rootfs_tail
}

assemble_rootfs_config() {
  if [ "${BUILD_PROFILE}" = "minimal" ] || [ "${FAST:-0}" = "1" ]; then
    _assemble_minimal_rootfs
  else
    _assemble_production_rootfs
  fi
}

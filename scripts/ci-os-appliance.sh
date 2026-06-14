#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() {
  printf 'ci-os-appliance: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_executable() {
  [ -x "$1" ] || fail "missing executable: $1"
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

assert_runlevel_service() {
  rootfs="$1"
  service="$2"
  link="${rootfs}/etc/runlevels/default/${service}"
  [ -L "${link}" ] || fail "missing default runlevel service: ${service}"
  [ "$(readlink "${link}")" = "/etc/init.d/${service}" ] || fail "bad runlevel target for ${service}"
}

test -L CLAUDE.md || fail "CLAUDE.md must be a symlink"
[ "$(readlink CLAUDE.md)" = "AGENTS.md" ] || fail "CLAUDE.md must point to AGENTS.md"
[ ! -e src/rv8 ] || fail "src/rv8 must stay deleted"

for path in \
  system/appliance/scripts/select-backend.sh \
  system/appliance/scripts/oil-installer.sh \
  system/backends/void/scripts/build-rootfs.sh \
  system/backends/void/scripts/configure-rootfs.sh \
  system/backends/void/runit/seatd/run \
  system/backends/void/runit/alpenglow-kernel-policy/run \
  system/backends/void/runit/alpenglow-netd/run \
  system/backends/void/runit/alpenglow-session/run \
  system/backends/void/runit/alpenglow-zram/run \
  system/backends/void/runit/sold/run \
  system/alpine/scripts/configure-rootfs.sh \
  system/alpine/scripts/apply-kernel-policy.sh \
  system/alpine/scripts/apply-zram-policy.sh \
  system/alpine/scripts/audit-package-budget.sh \
  system/alpine/scripts/build-native-policy-modules.sh \
  system/alpine/scripts/build-glowfs-module.sh \
  system/alpine/scripts/build-rootfs-image.sh \
  system/alpine/scripts/validate-filesystem-plan.sh \
  system/glowfs/kernel/validate-glowfs-kernel.sh \
  system/alpine/kernel/validate-kernel-config.sh \
  system/alpine/scripts/alpenglow-session-start \
  system/alpine/scripts/alpenglow-servo-wrapper \
  system/alpine/scripts/stage-alpenglow-artifacts.sh \
  system/alpine/openrc/sold \
  system/alpine/openrc/alpenglow-session \
  system/alpine/openrc/alpenglow-kernel-policy \
  system/alpine/openrc/alpenglow-netd \
  system/alpine/openrc/alpenglow-zram \
  system/alpine/openrc/seatd
do
  assert_file "${path}"
  sh -n "${path}"
done
assert_file system/appliance/README.md
assert_file system/appliance/backend.schema.json
assert_file system/appliance/backends.json
assert_file system/appliance/filesystems/rootfs-layout.json
assert_file system/appliance/filesystems/state-mounts.json
assert_file system/appliance/installers/oil.json
assert_file system/backends/void/README.md
assert_file system/backends/void/backend.json
assert_file system/backends/void/packages-runtime.txt
assert_file system/backends/void/packages-dev.txt
assert_contains system/appliance/backends.json '"default": "void-musl-runit"'
assert_contains system/appliance/backends.json '"composition_model": "oasis-static"'
assert_contains system/appliance/installers/oil.json '"source": "https://github.com/tschk/oil"'
assert_contains system/appliance/installers/oil.json '"binary": "wax"'
assert_contains system/backends/void/backend.json '"package_manager": "oil"'
assert_contains system/backends/void/backend.json '"bootstrap_package_manager": "xbps"'
assert_contains system/appliance/scripts/oil-installer.sh 'OIL_ROOT'
assert_contains system/appliance/scripts/oil-installer.sh 'WAX_SYSTEM_PREFIX'
assert_contains system/appliance/scripts/oil-installer.sh 'system add --no-script'
assert_contains system/appliance/filesystems/rootfs-layout.json '"role": "immutable-system"'
assert_contains system/appliance/filesystems/rootfs-layout.json '"glowfs"'
assert_contains system/appliance/filesystems/rootfs-layout.json '"erofs"'
assert_contains system/appliance/filesystems/rootfs-layout.json '"squashfs"'
assert_contains system/appliance/filesystems/rootfs-layout.json '"/etc/alpenglow/world"'
assert_not_contains system/appliance/filesystems/rootfs-layout.json '"/etc/apk/world.alpenglow"'
assert_contains system/appliance/filesystems/state-mounts.json '"target": "/var/lib/alpenglow"'
assert_contains system/appliance/filesystems/state-mounts.json '"target": "/home"'
assert_contains system/backends/void/backend.json '"id": "void-musl-runit"'
assert_contains system/backends/void/backend.json '"libc": "musl"'
assert_contains system/backends/void/backend.json '"init": "runit"'
assert_contains system/backends/void/backend.json '"installer": "oil"'
assert_contains system/backends/void/scripts/configure-rootfs.sh '"id": "oil"'
assert_contains system/backends/void/scripts/configure-rootfs.sh '"bootstrap": "xbps"'
assert_contains system/backends/void/backend.json '"composition_model": "oasis-static"'
assert_contains system/backends/void/packages-runtime.txt '^base-minimal$'
assert_contains system/backends/void/packages-runtime.txt '^runit$'
assert_contains system/backends/void/packages-runtime.txt '^seatd$'
assert_contains system/backends/void/packages-runtime.txt '^cage$'
assert_contains system/backends/void/packages-dev.txt '^base-devel$'
assert_contains system/backends/void/scripts/build-rootfs.sh 'x86_64-musl'
assert_contains system/backends/void/scripts/build-rootfs.sh 'current/musl'
assert_contains system/backends/void/scripts/build-rootfs.sh 'ALPENGLOW_OIL_SYSTEM_PACKAGES'
assert_contains system/backends/void/scripts/build-rootfs.sh 'oil-installer.sh'
assert_contains system/backends/void/scripts/configure-rootfs.sh 'world.void'
assert_contains system/backends/void/scripts/configure-rootfs.sh 'system/appliance/filesystems'
assert_contains system/backends/void/scripts/configure-rootfs.sh 'rm -rf "\$\{ROOTFS\}/etc/apk"'
assert_contains system/backends/void/scripts/configure-rootfs.sh '::wait:/etc/runit/2'
assert_contains system/backends/void/scripts/configure-rootfs.sh 'void-musl-runit'
assert_contains system/backends/void/scripts/configure-rootfs.sh 'oasis-static'
assert_contains system/backends/void/scripts/configure-rootfs.sh '/etc/runit/runsvdir/default'
assert_contains system/backends/void/runit/sold/run 'SOLD_UI_DIR'
assert_contains system/backends/void/runit/alpenglow-session/run 'alpenglow-session-start'
assert_executable system/appliance/scripts/select-backend.sh
[ "$(system/appliance/scripts/select-backend.sh)" = "${REPO_ROOT}/system/backends/void" ] || fail "default backend selector must resolve Void"
assert_file scripts/ci-qemu-appliance.sh
sh -n scripts/ci-qemu-appliance.sh
assert_file scripts/ci-qemu-glowfs-disk-root.sh
sh -n scripts/ci-qemu-glowfs-disk-root.sh
assert_file scripts/ci-glowfs-kernel-module.sh
sh -n scripts/ci-glowfs-kernel-module.sh
assert_contains scripts/ci-qemu-glowfs-disk-root.sh 'ALPENGLOW_RAM_ROOT=disk'
assert_contains scripts/ci-qemu-glowfs-disk-root.sh 'switching to disk root /dev/vda'
assert_contains scripts/ci-qemu-appliance.sh 'Starting alpenglow-kernel-policy'
assert_contains scripts/ci-qemu-appliance.sh 'Starting alpenglow-zram'
assert_contains scripts/ci-qemu-appliance.sh 'Cannot find Xwayland binary'

assert_file system/alpine/kernel-policy.json
assert_file system/alpine/filesystems/rootfs-layout.json
assert_file system/alpine/filesystems/state-mounts.json
assert_contains system/alpine/filesystems/rootfs-layout.json '"role": "immutable-system"'
assert_contains system/alpine/filesystems/rootfs-layout.json '"glowfs"'
assert_contains system/alpine/filesystems/rootfs-layout.json '"erofs"'
assert_contains system/alpine/filesystems/rootfs-layout.json '"squashfs"'
assert_contains system/alpine/filesystems/state-mounts.json '"target": "/var/lib/alpenglow"'
assert_contains system/alpine/filesystems/state-mounts.json '"target": "/home"'
assert_contains system/alpine/scripts/build-rootfs-image.sh 'mkfs.erofs'
assert_contains system/alpine/scripts/build-rootfs-image.sh 'mksquashfs'
assert_contains system/alpine/scripts/build-rootfs-image.sh 'glowfsctl mkfs'
assert_contains system/alpine/scripts/qemu-v0.sh 'build-rootfs-image.sh'
assert_contains system/alpine/scripts/qemu-v0.sh 'build-glowfs-module.sh'
assert_contains system/alpine/scripts/qemu-v0.sh 'ALPENGLOW_ROOTFS_FORMAT'
assert_contains system/alpine/scripts/qemu-v0.sh 'ALPENGLOW_ROOTFS_IMAGE_REQUIRED'
assert_contains system/alpine/qemu-v0.sh 'exec "\$\{SCRIPT_DIR\}/scripts/qemu-v0.sh" "\$@"'
assert_not_contains system/alpine/qemu-v0.sh 'mksquashfs|losetup|qemu-system'
assert_contains system/alpine/scripts/run-qemu.sh 'ALPENGLOW_ROOTFS_IMAGE'
assert_contains system/alpine/scripts/run-qemu.sh 'missing required rootfs image'
assert_contains system/alpine/scripts/run-qemu.sh 'virtio-blk-pci'
assert_contains system/alpine/scripts/build-qemu-initramfs.sh 'fallback_fstype'
assert_contains system/alpine/rootfs-overlay/init 'load_kernel_module_file'
assert_contains system/alpine/rootfs-overlay/init 'glowfs.ko'
assert_contains system/alpine/rootfs-overlay/init 'mount --move'
assert_contains system/alpine/rootfs-overlay/init 'switching to disk root'
assert_contains system/alpine/rootfs-overlay/init 'disk root mount failed'
assert_contains system/alpine/rootfs-overlay/init 'wait_for_device'
assert_contains system/alpine/rootfs-overlay/init 'loaded kernel module'
assert_contains system/alpine/rootfs-overlay/init 'prepare_disk_root_state'
assert_contains system/alpine/rootfs-overlay/init 'var/lib/alpenglow'
assert_file system/alpine/kernel/APKBUILD
assert_file system/alpine/kernel/README.md
assert_file system/alpine/kernel/alpenglow-internet-appliance.config
assert_file system/glowfs/kernel/glowfs_vfs.c
assert_file system/glowfs/kernel/glowfs_core.rs
assert_file system/glowfs/kernel/glowfs_format.h
assert_contains system/glowfs/kernel/glowfs_vfs.c 'mount_bdev'
assert_contains system/glowfs/kernel/glowfs_vfs.c 'register_filesystem'
assert_contains system/glowfs/kernel/glowfs_core.rs '#!\[no_std\]'
assert_contains system/glowfs/kernel/glowfs_core.rs 'glowfs_rust_validate_header'
system/glowfs/kernel/validate-glowfs-kernel.sh
assert_file system/native/kernel-policy-v/policy.v
assert_file system/native/kernel-policy-v/v.mod
assert_contains system/alpine/kernel-policy.json '"profile": "internet-appliance"'
assert_contains system/alpine/kernel/APKBUILD '^pkgname=linux-alpenglow-appliance$'
assert_contains system/alpine/kernel/APKBUILD 'validate-kernel-config.sh'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_CGROUPS=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_RUST=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_ZRAM=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_VIRTIO_NET=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_DRM_VIRTIO_GPU=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_SECCOMP_FILTER=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_SECURITY_LANDLOCK=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^CONFIG_TCP_CONG_BBR=y$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^# CONFIG_USB_STORAGE is not set$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^# CONFIG_BLUETOOTH is not set$'
assert_contains system/alpine/kernel/alpenglow-internet-appliance.config '^# CONFIG_CIFS is not set$'
assert_contains system/alpine/kernel/validate-kernel-config.sh 'CONFIG_SECURITY_LANDLOCK'
system/alpine/kernel/validate-kernel-config.sh
assert_contains system/alpine/kernel-policy.json '"net.core.somaxconn"'
assert_contains system/alpine/scripts/build-native-policy-modules.sh 'https://github.com/tschk/equilibrium'
assert_contains system/alpine/scripts/build-native-policy-modules.sh 'libalpenglow_native_policy_v.so'
assert_contains system/alpine/scripts/build-native-policy-modules.sh 'native policy userland module'
assert_not_contains system/alpine/scripts/build-native-policy-modules.sh 'Built V kernel'
assert_contains system/alpine/scripts/build-glowfs-module.sh 'linux-virt-dev'
assert_contains system/alpine/scripts/build-glowfs-module.sh 'kernel-release'
assert_contains system/alpine/scripts/stage-alpenglow-artifacts.sh 'NATIVE_POLICY_REQUIRED'
assert_contains system/alpine/scripts/stage-alpenglow-artifacts.sh '/usr/local/lib/alpenglow/native-policy'
assert_contains system/alpine/scripts/stage-alpenglow-artifacts.sh 'GLOWFS_MODULE'
assert_contains system/alpine/scripts/stage-alpenglow-artifacts.sh '/usr/local/lib/alpenglow/kernel/glowfs.ko'
assert_contains system/alpine/scripts/stage-alpenglow-artifacts.sh 'cp -R "\$\{UI_BUILD_DIR\}" "\$\{ROOTFS\}/usr/local/share/alpenglow/bundle"'
assert_contains system/alpine/scripts/stage-alpenglow-artifacts.sh 'bundle/terminal'
assert_contains system/alpine/stage-alpenglow-artifacts.sh 'scripts/stage-alpenglow-artifacts.sh'
assert_not_contains system/alpine/scripts/stage-alpenglow-artifacts.sh '/usr/local/share/alpenglow/ui'
assert_contains system/alpine/scripts/ensure-linux-runtime-binaries.sh 'build_netd_linux'
assert_contains system/alpine/scripts/qemu-v0.sh 'ALPENGLOW_NETD_BIN'
assert_contains system/native/kernel-policy-v/policy.v 'alpenglow_renderer_cpu_weight'
assert_contains system/native/kernel-policy-v/v.mod "license: 'MPL-2.0'"
assert_contains system/alpine/openrc/alpenglow-session '^respawn=YES$'
assert_contains system/alpine/openrc/alpenglow-session 'need sold seatd'
assert_contains system/alpine/openrc/sold 'need localmount networking'
assert_contains system/alpine/openrc/sold 'alpenglow-netd'
assert_not_contains system/alpine/rootfs-overlay/etc/conf.d/sold 'SOLD_UI_DIR'
assert_contains system/alpine/openrc/alpenglow-kernel-policy 'apply-kernel-policy.sh'
assert_contains system/alpine/openrc/alpenglow-kernel-policy '/run/alpenglow/resolv.conf'
assert_contains system/alpine/openrc/alpenglow-netd 'alpenglow-netd'
assert_contains system/alpine/openrc/alpenglow-netd 'before sold alpenglow-session'
assert_contains system/alpine/openrc/alpenglow-zram 'apply-zram-policy.sh'
assert_contains system/alpine/openrc/seatd '^command_background="yes"$'
assert_file system/alpine/rootfs-overlay/etc/udhcpc/udhcpc.conf
assert_contains system/alpine/rootfs-overlay/etc/udhcpc/udhcpc.conf '^RESOLV_CONF="/run/alpenglow/resolv\.conf"$'
assert_file system/alpine/rootfs-overlay/etc/modprobe.d/alpenglow-browser-appliance.conf
assert_file system/alpine/rootfs-overlay/etc/modules-load.d/alpenglow-browser-appliance.conf
assert_contains system/alpine/rootfs-overlay/etc/modprobe.d/alpenglow-browser-appliance.conf '^blacklist bluetooth$'
assert_contains system/alpine/rootfs-overlay/etc/modprobe.d/alpenglow-browser-appliance.conf '^blacklist usb_storage$'
assert_contains system/alpine/rootfs-overlay/etc/modules-load.d/alpenglow-browser-appliance.conf '^zram$'
assert_contains system/alpine/rootfs-overlay/init 'mount -t cgroup2 cgroup2 /sys/fs/cgroup'
assert_contains system/alpine/rootfs-overlay/init 'mount -t devpts devpts /dev/pts'
assert_contains system/alpine/rootfs-overlay/init 'ln -sf pts/ptmx /dev/ptmx'
assert_contains system/alpine/rootfs-overlay/etc/inittab '^::wait:/sbin/openrc default$'
assert_not_contains system/alpine/rootfs-overlay/etc/inittab 'alpenglow-session-start'

assert_contains system/alpine/scripts/apply-kernel-policy.sh 'load_kernel_module virtio_net'
assert_contains system/alpine/scripts/apply-kernel-policy.sh 'load_kernel_module glowfs'
assert_contains system/alpine/scripts/apply-kernel-policy.sh 'ALPENGLOW_GLOWFS_MODULE'
assert_contains system/alpine/scripts/configure-rootfs.sh '"id": "oil"'
assert_contains system/alpine/scripts/configure-rootfs.sh '"bootstrap": "apk"'
assert_contains system/alpine/scripts/apply-kernel-policy.sh 'load_kernel_module_file'
assert_contains system/alpine/scripts/apply-kernel-policy.sh 'alpenglow-kernelctl'
assert_contains system/alpine/scripts/apply-kernel-policy.sh 'cgroup.subtree_control'
assert_contains system/alpine/scripts/apply-kernel-policy.sh 'memory.high'
assert_contains system/alpine/scripts/apply-kernel-policy.sh 'io.weight'
assert_contains system/alpine/scripts/apply-zram-policy.sh 'modprobe zram'
assert_contains system/alpine/scripts/apply-zram-policy.sh 'swapon -p 100 /dev/zram0'
assert_contains system/alpine/scripts/audit-package-budget.sh 'ALPENGLOW_MAX_RUNTIME_PACKAGES'
assert_contains system/alpine/packages-v0.txt '^font-dejavu$'
assert_not_contains system/alpine/packages-v0.txt '^xwayland$|^gcompat$|^font-noto$'
assert_contains system/alpine/scripts/alpenglow-session-start 'ALPENGLOW_RUNTIME_STATE_ENV'
assert_contains system/alpine/scripts/alpenglow-session-start 'ALPENGLOW_KERNEL_POLICY_REQUIRED'
assert_contains system/alpine/scripts/alpenglow-session-start 'wait_for_seatd_socket'
assert_contains system/alpine/scripts/alpenglow-session-start 'LIBSEAT_BACKEND=direct'
assert_contains system/alpine/rootfs-overlay/etc/conf.d/alpenglow-session '^ALPENGLOW_KERNEL_POLICY_REQUIRED=1$'
assert_contains system/alpine/rootfs-overlay/etc/conf.d/alpenglow-session '^ALPENGLOW_SESSION_X11_FALLBACK=0$'
assert_contains system/alpine/scripts/alpenglow-session-start 'WLR_XWAYLAND'
assert_contains system/alpine/scripts/alpenglow-session-start 'alpenglow-kernelctl attach --group'
assert_contains system/alpine/scripts/alpenglow-session-start 'attach_to_cgroup browser'
assert_contains system/alpine/scripts/alpenglow-servo-wrapper 'attach_to_cgroup foreground-renderer'
assert_contains system/alpine/scripts/alpenglow-servo-wrapper 'alpenglow-kernelctl attach --group'
assert_contains system/alpine/scripts/alpenglow-servo-wrapper 'ALPENGLOW_SERVO_LOG_FILTER'
assert_contains system/alpine/scripts/alpenglow-servo-wrapper 'filter_servo_logs'
assert_contains system/alpine/openrc/sold 'attach_to_cgroup system'
assert_contains system/alpine/openrc/sold 'alpenglow-kernelctl attach --group'
assert_contains system/alpine/services.json '"id": "networking"'
assert_contains system/alpine/services.json '"id": "alpenglow-netd"'
assert_contains system/alpine/services.json '"id": "alpenglow-zram"'
assert_contains system/alpine/services.json '"id": "sold"'
assert_contains system/alpine/services.json '"id": "alpenglow-session"'
assert_not_contains system/alpine/scripts/stage-alpenglow-artifacts.sh 'src/rv8|release/rv8|cargo .*rv8'
assert_not_contains system/alpine/scripts/configure-rootfs.sh 'dev-signature-placeholder|fake|placeholder signature'

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT INT TERM
mkdir -p "${tmp_root}/etc/init.d" "${tmp_root}/etc/runlevels/default"
: >"${tmp_root}/etc/passwd"
: >"${tmp_root}/etc/group"
: >"${tmp_root}/etc/shadow"
for service in local networking; do
  printf '#!/sbin/openrc-run\n' >"${tmp_root}/etc/init.d/${service}"
done

system/alpine/scripts/configure-rootfs.sh "${tmp_root}" >/dev/null

for service in networking seatd alpenglow-kernel-policy alpenglow-zram alpenglow-netd sold alpenglow-session; do
  assert_runlevel_service "${tmp_root}" "${service}"
done

assert_file "${tmp_root}/etc/alpenglow/services.json"
assert_file "${tmp_root}/etc/alpenglow/system.json"
assert_file "${tmp_root}/etc/alpenglow/kernel-policy.json"
assert_file "${tmp_root}/etc/alpenglow/package-manager.json"
assert_file "${tmp_root}/etc/alpenglow/filesystems/rootfs-layout.json"
assert_file "${tmp_root}/etc/alpenglow/filesystems/state-mounts.json"
assert_file "${tmp_root}/var/lib/alpenglow/system/plugin-installs.json"
assert_executable "${tmp_root}/etc/init.d/alpenglow-kernel-policy"
assert_executable "${tmp_root}/etc/init.d/alpenglow-netd"
assert_executable "${tmp_root}/etc/init.d/alpenglow-zram"
assert_executable "${tmp_root}/usr/local/bin/apply-kernel-policy.sh"
assert_executable "${tmp_root}/usr/local/bin/apply-zram-policy.sh"
assert_executable "${tmp_root}/usr/local/bin/alpenglow-session-start"
assert_executable "${tmp_root}/usr/local/bin/alpenglow-servo-wrapper"
assert_not_contains "${tmp_root}/etc/inittab" 'alpenglow-session-start'
assert_contains "${tmp_root}/etc/rc.conf" '^rc_parallel="YES"$'
assert_contains "${tmp_root}/etc/sysctl.d/99-alpenglow-internet-os.conf" '^net.core.somaxconn=4096$'
assert_contains "${tmp_root}/etc/modprobe.d/alpenglow-browser-appliance.conf" '^blacklist usb_storage$'
assert_contains "${tmp_root}/etc/modules-load.d/alpenglow-browser-appliance.conf" '^zram$'
assert_contains "${tmp_root}/etc/udhcpc/udhcpc.conf" '^RESOLV_CONF="/run/alpenglow/resolv\.conf"$'
assert_contains "${tmp_root}/var/lib/alpenglow/system/plugin-installs.json" '"plugins": \[\]'
assert_contains "${tmp_root}/etc/alpenglow/services.json" '"id": "seatd"'
assert_contains "${tmp_root}/etc/alpenglow/services.json" '"id": "alpenglow-kernel-policy"'
assert_contains "${tmp_root}/etc/alpenglow/services.json" '"id": "alpenglow-netd"'
assert_contains "${tmp_root}/etc/alpenglow/services.json" '"id": "alpenglow-zram"'
assert_contains "${tmp_root}/etc/alpenglow/services.json" '"id": "alpenglow-session"'
system/alpine/scripts/validate-filesystem-plan.sh "${tmp_root}" >/dev/null
assert_contains "${tmp_root}/etc/alpenglow/filesystems/fstab.plan" '^alpenglow-root / glowfs ro,nodev 0 0$'
[ ! -e "${tmp_root}/etc/runlevels/default/local" ] || fail "local must not block browser appliance boot"

printf 'ci-os-appliance: ok\n'

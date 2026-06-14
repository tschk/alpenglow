#!/bin/sh
set -eu

CONFIG_FILE="${1:-$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/alpenglow-internet-appliance.config}"
KERNEL_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
METADATA_FILE="${ALPENGLOW_KERNEL_METADATA:-${KERNEL_DIR}/hybrid-kernel.json}"

if [ ! -f "${CONFIG_FILE}" ]; then
  printf 'validate-kernel-config: missing config: %s\n' "${CONFIG_FILE}" >&2
  exit 1
fi

failures=0

option_value() {
  option="$1"
  awk -v option="${option}" '
    $0 == option "=y" { value = "y" }
    $0 == option "=m" { value = "m" }
    $0 == option "=n" { value = "n" }
    $0 ~ "^" option "=" { value = substr($0, length(option) + 2) }
    $0 == "# " option " is not set" { value = "unset" }
    END {
      if (value != "") {
        print value
      }
    }
  ' "${CONFIG_FILE}"
}

require_enabled() {
  option="$1"
  value="$(option_value "${option}")"
  case "${value}" in
    y|m)
      return 0
      ;;
  esac
  printf 'validate-kernel-config: %s must be enabled, found %s\n' "${option}" "${value:-missing}" >&2
  failures=$((failures + 1))
}

require_builtin() {
  option="$1"
  value="$(option_value "${option}")"
  if [ "${value}" = "y" ]; then
    return 0
  fi
  printf 'validate-kernel-config: %s must be built in, found %s\n' "${option}" "${value:-missing}" >&2
  failures=$((failures + 1))
}

require_disabled() {
  option="$1"
  value="$(option_value "${option}")"
  case "${value}" in
    unset|n)
      return 0
      ;;
  esac
  printf 'validate-kernel-config: %s must be disabled, found %s\n' "${option}" "${value:-missing}" >&2
  failures=$((failures + 1))
}

require_value() {
  option="$1"
  expected="$2"
  value="$(option_value "${option}")"
  if [ "${value}" = "${expected}" ]; then
    return 0
  fi
  printf 'validate-kernel-config: %s must be %s, found %s\n' "${option}" "${expected}" "${value:-missing}" >&2
  failures=$((failures + 1))
}

require_file() {
  file="$1"
  if [ -f "${file}" ]; then
    return 0
  fi
  printf 'validate-kernel-config: missing metadata: %s\n' "${file}" >&2
  failures=$((failures + 1))
}

require_contains() {
  file="$1"
  pattern="$2"
  if [ -f "${file}" ] && grep -Fq "${pattern}" "${file}"; then
    return 0
  fi
  printf 'validate-kernel-config: %s must contain %s\n' "${file}" "${pattern}" >&2
  failures=$((failures + 1))
}

for option in \
  CONFIG_CGROUPS \
  CONFIG_RUST \
  CONFIG_CGROUP_BPF \
  CONFIG_CGROUP_PIDS \
  CONFIG_CPUSETS \
  CONFIG_MEMCG \
  CONFIG_LRU_GEN \
  CONFIG_LRU_GEN_ENABLED \
  CONFIG_BLK_CGROUP \
  CONFIG_NAMESPACES \
  CONFIG_SECCOMP \
  CONFIG_SECCOMP_FILTER \
  CONFIG_SECURITY_LANDLOCK \
  CONFIG_NET_SCH_FQ \
  CONFIG_TCP_CONG_BBR \
  CONFIG_ZRAM \
  CONFIG_ZSMALLOC \
  CONFIG_SWAP \
  CONFIG_EROFS_FS \
  CONFIG_EROFS_FS_ZIP \
  CONFIG_VIRTIO \
  CONFIG_VIRTIO_PCI \
  CONFIG_VIRTIO_BLK \
  CONFIG_VIRTIO_NET \
  CONFIG_VIRTIO_CONSOLE \
  CONFIG_HW_RANDOM_VIRTIO \
  CONFIG_DRM \
  CONFIG_DRM_KMS_HELPER \
  CONFIG_DRM_FBDEV_EMULATION \
  CONFIG_DRM_VIRTIO_GPU \
  CONFIG_DRM_SIMPLEDRM \
  CONFIG_EXT4_FS \
  CONFIG_SQUASHFS \
  CONFIG_SQUASHFS_ZSTD \
  CONFIG_OVERLAY_FS \
  CONFIG_TMPFS \
  CONFIG_DEVTMPFS \
  CONFIG_DEVTMPFS_MOUNT
do
  require_enabled "${option}"
done

for option in \
  CONFIG_CGROUPS \
  CONFIG_RUST \
  CONFIG_SECCOMP \
  CONFIG_SECURITY_LANDLOCK \
  CONFIG_VIRTIO \
  CONFIG_VIRTIO_PCI \
  CONFIG_VIRTIO_BLK \
  CONFIG_VIRTIO_NET \
  CONFIG_DRM \
  CONFIG_DRM_VIRTIO_GPU \
  CONFIG_ZRAM \
  CONFIG_LRU_GEN \
  CONFIG_EXT4_FS \
  CONFIG_EROFS_FS \
  CONFIG_TMPFS \
  CONFIG_DEVTMPFS
do
  require_builtin "${option}"
done

require_value CONFIG_DEFAULT_TCP_CONG '"bbr"'

require_file "${METADATA_FILE}"
require_file "${KERNEL_DIR}/patch-series/bore-style.json"
require_file "${KERNEL_DIR}/patches/series"

for token in \
  '"id": "alpenglow-hybrid-default"' \
  '"default": true' \
  '"mode": "single_default"' \
  '"hardware_adjustment": "runtime_capability_probe"' \
  '"in_tree_path": "system/alpine/kernel/linux"' \
  '"path": "patches/series"' \
  '"fallback_boot"' \
  '"metrics_gates"' \
  '"mglru"' \
  '"zram"' \
  '"seccomp"' \
  '"landlock"' \
  '"bbr_fq"' \
  '"glowfs"' \
  '"erofs"' \
  '"squashfs"' \
  '"damon"' \
  '"sched_ext"' \
  '"preempt_rt"' \
  '"patch-series/bore-style.json"'
do
  require_contains "${METADATA_FILE}" "${token}"
done

for token in \
  '"id": "bore-style-scheduler-lane"' \
  '"lane": "direct-source-edit-or-patch-queue"' \
  '"source_policy": "in-tree-source-expected"' \
  '"source_path": "system/alpine/kernel/linux"' \
  '"queue_path": "system/alpine/kernel/patches/series"'
do
  require_contains "${KERNEL_DIR}/patch-series/bore-style.json" "${token}"
done

for option in \
  CONFIG_ACPI \
  CONFIG_ANDROID \
  CONFIG_APPLETALK \
  CONFIG_ATM \
  CONFIG_BCACHEFS_FS \
  CONFIG_BFS_FS \
  CONFIG_BLUETOOTH \
  CONFIG_BTRFS_FS \
  CONFIG_CAN \
  CONFIG_CEPH_FS \
  CONFIG_CIFS \
  CONFIG_DLM \
  CONFIG_DRM_NOUVEAU \
  CONFIG_DRM_RADEON \
  CONFIG_DRM_XE \
  CONFIG_FIREWIRE \
  CONFIG_GFS2_FS \
  CONFIG_HAMRADIO \
  CONFIG_HFS_FS \
  CONFIG_HFSPLUS_FS \
  CONFIG_INFINIBAND \
  CONFIG_IP_DCCP \
  CONFIG_IP_SCTP \
  CONFIG_IPX \
  CONFIG_ISDN \
  CONFIG_JFS_FS \
  CONFIG_NFC \
  CONFIG_NFS_FS \
  CONFIG_OCFS2_FS \
  CONFIG_PPP \
  CONFIG_REISERFS_FS \
  CONFIG_SCSI \
  CONFIG_SMB_SERVER \
  CONFIG_SOUND \
  CONFIG_USB_GADGET \
  CONFIG_USB_STORAGE \
  CONFIG_WIMAX \
  CONFIG_WIRELESS_EXT \
  CONFIG_X25
do
  require_disabled "${option}"
done

if [ "${failures}" -ne 0 ]; then
  printf 'validate-kernel-config: failed with %s error(s)\n' "${failures}" >&2
  exit 1
fi

printf 'validate-kernel-config: ok %s\n' "${CONFIG_FILE}"

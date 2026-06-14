#!/bin/sh
set -eu

SOLILOQUY_KERNEL_POLICY_FILE="${SOLILOQUY_KERNEL_POLICY_FILE:-/etc/soliloquy/kernel-policy.json}"
SOLILOQUY_HYBRID_KERNEL_METADATA="${SOLILOQUY_HYBRID_KERNEL_METADATA:-/usr/share/soliloquy/kernel/hybrid-kernel.json}"
SOLILOQUY_RUNTIME_STATE_ENV="${SOLILOQUY_RUNTIME_STATE_ENV:-/run/soliloquy/runtime-state.env}"
SOLILOQUY_SOLFS_MODULE="${SOLILOQUY_SOLFS_MODULE:-/usr/local/lib/soliloquy/kernel/solfs.ko}"

if [ -x /usr/local/bin/sol-kernelctl ]; then
  exec /usr/local/bin/sol-kernelctl \
    --policy "${SOLILOQUY_KERNEL_POLICY_FILE}" \
    --runtime-state "${SOLILOQUY_RUNTIME_STATE_ENV}"
fi

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

record_feature() {
  key="$1"
  value="$2"
  record_runtime_state "SOLILOQUY_KERNEL_FEATURE_${key}" "${value}"
}

apply_sysctl() {
  key="$1"
  value="$2"
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -q -w "${key}=${value}" >/dev/null 2>&1 || true
  fi
}

record_path_capability() {
  key="$1"
  path="$2"
  if [ -e "${path}" ]; then
    record_runtime_state "${key}" active
  else
    record_runtime_state "${key}" unavailable
  fi
}

record_filesystem_capability() {
  key="$1"
  fs="$2"
  if grep -qw "${fs}" /proc/filesystems 2>/dev/null; then
    record_runtime_state "${key}" active
  else
    record_runtime_state "${key}" unavailable
  fi
}

record_sysctl_value() {
  key="$1"
  sysctl_key="$2"
  if command -v sysctl >/dev/null 2>&1; then
    value="$(sysctl -n "${sysctl_key}" 2>/dev/null || true)"
    if [ -n "${value}" ]; then
      record_runtime_state "${key}" "${value}"
      return 0
    fi
  fi
  record_runtime_state "${key}" unavailable
}

load_kernel_module() {
  module="$1"
  if command -v modprobe >/dev/null 2>&1; then
    modprobe "${module}" >/dev/null 2>&1 || true
  fi
}

load_kernel_module_file() {
  module_path="$1"
  if [ -f "${module_path}" ] && command -v insmod >/dev/null 2>&1; then
    insmod "${module_path}" >/dev/null 2>&1 || true
  fi
}

enable_controller() {
  controller="$1"
  if [ -f /sys/fs/cgroup/cgroup.subtree_control ]; then
    printf '+%s\n' "${controller}" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
  fi
}

set_cgroup_value() {
  group="$1"
  file="$2"
  value="$3"
  path="/sys/fs/cgroup/soliloquy/${group}/${file}"
  if [ -f "${path}" ]; then
    printf '%s\n' "${value}" >"${path}" 2>/dev/null || true
  fi
}

prepare_group() {
  group="$1"
  if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    mkdir -p "/sys/fs/cgroup/soliloquy/${group}" 2>/dev/null || true
  fi
}

configure_group() {
  group="$1"
  cpu_weight="$2"
  io_weight="$3"
  memory_high="$4"
  memory_max="$5"
  pids_max="$6"
  prepare_group "${group}"
  set_cgroup_value "${group}" cpu.weight "${cpu_weight}"
  set_cgroup_value "${group}" io.weight "${io_weight}"
  set_cgroup_value "${group}" memory.high "${memory_high}"
  if [ -n "${memory_max}" ]; then
    set_cgroup_value "${group}" memory.max "${memory_max}"
  fi
  set_cgroup_value "${group}" pids.max "${pids_max}"
}

controller_available() {
  controller="$1"
  [ -r /sys/fs/cgroup/cgroup.controllers ] && grep -qw "${controller}" /sys/fs/cgroup/cgroup.controllers
}

record_controller_feature() {
  controller="$1"
  key="$2"
  if controller_available "${controller}"; then
    record_feature "${key}" 1
  else
    record_feature "${key}" 0
  fi
}

if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  record_feature CGROUP_V2 1
else
  record_feature CGROUP_V2 0
fi

record_controller_feature cpu CPU_CONTROLLER
record_controller_feature io IO_CONTROLLER
record_controller_feature memory MEMORY_CONTROLLER
record_controller_feature pids PIDS_CONTROLLER

if [ -r /proc/sys/net/ipv4/tcp_available_congestion_control ] && grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
  record_feature BBR 1
else
  record_feature BBR 0
fi

if [ -e /proc/sys/net/ipv4/tcp_fastopen ]; then
  record_feature TCP_FASTOPEN 1
else
  record_feature TCP_FASTOPEN 0
fi

if [ -d /sys/module/virtio_gpu ]; then
  record_feature VIRTIO_GPU 1
else
  record_feature VIRTIO_GPU 0
fi

if [ -f "${SOLILOQUY_KERNEL_POLICY_FILE}" ]; then
  record_runtime_state SOLILOQUY_KERNEL_POLICY_FILE "${SOLILOQUY_KERNEL_POLICY_FILE}"
fi

if [ -f "${SOLILOQUY_HYBRID_KERNEL_METADATA}" ]; then
  record_runtime_state SOLILOQUY_HYBRID_KERNEL_METADATA "${SOLILOQUY_HYBRID_KERNEL_METADATA}"
fi

record_runtime_state SOLILOQUY_KERNEL_SOURCE_MODE external-or-in-tree
record_runtime_state SOLILOQUY_KERNEL_SOURCE_IN_TREE system/alpine/kernel/linux
record_runtime_state SOLILOQUY_KERNEL_SOURCE_ENV SOLILOQUY_KERNEL_SOURCE
if [ -n "${SOLILOQUY_KERNEL_SOURCE:-}" ]; then
  record_runtime_state SOLILOQUY_KERNEL_SOURCE "${SOLILOQUY_KERNEL_SOURCE}"
fi
if [ -d /usr/src/soliloquy-linux ] || [ -d /usr/src/linux ] || [ -d /work/system/alpine/kernel/linux ]; then
  record_runtime_state SOLILOQUY_KERNEL_SOURCE_IN_TREE_PRESENT 1
else
  record_runtime_state SOLILOQUY_KERNEL_SOURCE_IN_TREE_PRESENT 0
fi
if [ -s /usr/share/soliloquy/kernel/patches/series ] || [ -s /work/system/alpine/kernel/patches/series ]; then
  record_runtime_state SOLILOQUY_KERNEL_PATCH_QUEUE active
else
  record_runtime_state SOLILOQUY_KERNEL_PATCH_QUEUE unavailable
fi
if [ -f /usr/share/soliloquy/kernel/patch-series/bore-style.json ] || [ -f /work/system/alpine/kernel/patch-series/bore-style.json ]; then
  record_runtime_state SOLILOQUY_KERNEL_BORE_LANE active
else
  record_runtime_state SOLILOQUY_KERNEL_BORE_LANE unavailable
fi

load_kernel_module virtio_pci
load_kernel_module virtio_net
load_kernel_module virtio_rng
load_kernel_module virtio_gpu
load_kernel_module erofs
load_kernel_module squashfs
load_kernel_module solfs
load_kernel_module_file "${SOLILOQUY_SOLFS_MODULE}"

apply_sysctl net.core.somaxconn 4096
apply_sysctl net.core.default_qdisc fq
apply_sysctl net.ipv4.tcp_congestion_control bbr
apply_sysctl net.ipv4.tcp_fastopen 3
apply_sysctl net.ipv4.tcp_fin_timeout 15
apply_sysctl net.ipv4.tcp_keepalive_time 60
apply_sysctl net.ipv4.tcp_mtu_probing 1
apply_sysctl net.ipv4.tcp_syncookies 1
apply_sysctl net.ipv4.tcp_tw_reuse 1
apply_sysctl net.ipv4.ip_forward 0
apply_sysctl net.ipv4.conf.all.accept_redirects 0
apply_sysctl net.ipv4.conf.all.rp_filter 2
apply_sysctl net.ipv4.conf.all.send_redirects 0
apply_sysctl vm.swappiness 20
apply_sysctl vm.vfs_cache_pressure 50
apply_sysctl kernel.unprivileged_bpf_disabled 1

record_path_capability SOLILOQUY_KERNEL_CAP_MGLRU /sys/kernel/mm/lru_gen/enabled
record_path_capability SOLILOQUY_KERNEL_CAP_ZRAM /sys/block/zram0
record_path_capability SOLILOQUY_KERNEL_CAP_DAMON /sys/kernel/mm/damon/admin
record_path_capability SOLILOQUY_KERNEL_CAP_SECCOMP /proc/sys/kernel/seccomp/actions_avail
record_path_capability SOLILOQUY_KERNEL_CAP_SCHED_EXT /sys/kernel/sched_ext
record_path_capability SOLILOQUY_KERNEL_CAP_PREEMPT_RT /sys/kernel/realtime
if [ -d /proc/sys/kernel/landlock ] || [ -e /proc/sys/kernel/landlock/restrict_self ]; then
  record_runtime_state SOLILOQUY_KERNEL_CAP_LANDLOCK active
else
  record_runtime_state SOLILOQUY_KERNEL_CAP_LANDLOCK unavailable
fi
record_filesystem_capability SOLILOQUY_KERNEL_CAP_SOLFS solfs
record_filesystem_capability SOLILOQUY_KERNEL_CAP_EROFS erofs
record_filesystem_capability SOLILOQUY_KERNEL_CAP_SQUASHFS squashfs
record_sysctl_value SOLILOQUY_KERNEL_NET_QDISC net.core.default_qdisc
record_sysctl_value SOLILOQUY_KERNEL_TCP_CC net.ipv4.tcp_congestion_control

if [ -r /proc/pressure/cpu ]; then
  record_runtime_state SOLILOQUY_PRESSURE_PSI_CPU active
else
  record_runtime_state SOLILOQUY_PRESSURE_PSI_CPU unavailable
fi
if [ -r /proc/pressure/memory ]; then
  record_runtime_state SOLILOQUY_PRESSURE_PSI_MEMORY active
else
  record_runtime_state SOLILOQUY_PRESSURE_PSI_MEMORY unavailable
fi
if [ -r /proc/pressure/io ]; then
  record_runtime_state SOLILOQUY_PRESSURE_PSI_IO active
else
  record_runtime_state SOLILOQUY_PRESSURE_PSI_IO unavailable
fi
if [ -r /proc/pressure/memory ]; then
  memory_some_avg10="$(awk '/some/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { split($i, a, "="); print a[2] } }' /proc/pressure/memory 2>/dev/null || true)"
  case "${memory_some_avg10}" in
    ""|0.00|0.0|0)
      record_runtime_state SOLILOQUY_PRESSURE_LEVEL normal
      ;;
    *)
      record_runtime_state SOLILOQUY_PRESSURE_LEVEL observable
      ;;
  esac
else
  record_runtime_state SOLILOQUY_PRESSURE_LEVEL unknown
fi

if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  mkdir -p /sys/fs/cgroup/soliloquy 2>/dev/null || true
  for controller in cpu io memory pids; do
    enable_controller "${controller}"
  done

  configure_group system 100 100 256M "" 128
  configure_group network 250 500 384M 640M 192
  configure_group browser 350 300 768M 1024M 256
  configure_group foreground-renderer 800 800 1536M 2304M 512
  configure_group background-renderer 250 200 768M 1280M 384
  configure_group frozen-renderer 50 50 384M 768M 256
  configure_group discardable-renderer 10 10 128M 256M 128
  configure_group gpu-compositor 900 300 512M 768M 192

  record_runtime_state SOLILOQUY_KERNEL_POLICY_CGROUPS active
else
  record_runtime_state SOLILOQUY_KERNEL_POLICY_CGROUPS unavailable
fi

record_runtime_state SOLILOQUY_KERNEL_POLICY_PROFILE internet-appliance

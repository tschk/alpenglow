#!/bin/sh
set -eu

ALPENGLOW_RUNTIME_STATE_ENV="${ALPENGLOW_RUNTIME_STATE_ENV:-/run/alpenglow/runtime-state.env}"
ALPENGLOW_CGROUP_ROOT="${ALPENGLOW_CGROUP_ROOT:-/sys/fs/cgroup/alpenglow}"
ALPENGLOW_PRESSURE_INTERVAL_SECONDS="${ALPENGLOW_PRESSURE_INTERVAL_SECONDS:-2}"
ALPENGLOW_PRESSURE_ONESHOT="${ALPENGLOW_PRESSURE_ONESHOT:-0}"

mkdir -p "$(dirname "${ALPENGLOW_RUNTIME_STATE_ENV}")"

record_runtime_state() {
  key="$1"
  value="$2"
  tmp="${ALPENGLOW_RUNTIME_STATE_ENV}.$$"
  if [ -f "${ALPENGLOW_RUNTIME_STATE_ENV}" ]; then
    grep -v "^${key}=" "${ALPENGLOW_RUNTIME_STATE_ENV}" >"${tmp}" || true
  else
    : >"${tmp}"
  fi
  printf '%s=%s\n' "${key}" "${value}" >>"${tmp}"
  mv "${tmp}" "${ALPENGLOW_RUNTIME_STATE_ENV}"
}

set_cgroup_value() {
  group="$1"
  file="$2"
  value="$3"
  path="${ALPENGLOW_CGROUP_ROOT}/${group}/${file}"
  if [ -f "${path}" ]; then
    printf '%s\n' "${value}" >"${path}" 2>/dev/null || true
  fi
}

set_group_policy() {
  group="$1"
  cpu="$2"
  io="$3"
  high="$4"
  max="$5"
  pids="$6"
  set_cgroup_value "${group}" cpu.weight "${cpu}"
  set_cgroup_value "${group}" io.weight "${io}"
  set_cgroup_value "${group}" memory.high "${high}"
  set_cgroup_value "${group}" memory.max "${max}"
  set_cgroup_value "${group}" pids.max "${pids}"
}

set_group_freeze() {
  group="$1"
  value="$2"
  set_cgroup_value "${group}" cgroup.freeze "${value}"
}

classify_pressure() {
  if [ ! -r /proc/pressure/memory ]; then
    printf '%s\n' unknown
    return 0
  fi
  awk '
    /^some/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^avg10=/) {
          split($i, a, "=")
          avg = a[2] + 0
        }
      }
    }
    END {
      if (avg >= 40) print "critical"
      else if (avg >= 20) print "pressure"
      else if (avg >= 5) print "constrained"
      else print "normal"
    }
  ' /proc/pressure/memory
}

apply_pressure_level() {
  level="$1"
  record_runtime_state ALPENGLOW_PRESSURE_LEVEL "${level}"
  case "${level}" in
    normal)
      set_group_policy background-renderer 250 200 768M 1280M 384
      set_group_policy frozen-renderer 50 50 384M 768M 256
      set_group_policy discardable-renderer 10 10 128M 256M 128
      set_group_freeze frozen-renderer 0
      ;;
    constrained)
      set_group_policy background-renderer 150 100 512M 960M 256
      set_group_policy frozen-renderer 25 25 256M 512M 192
      set_group_policy discardable-renderer 10 10 96M 192M 96
      set_group_freeze frozen-renderer 0
      ;;
    pressure)
      set_group_policy background-renderer 75 50 384M 768M 192
      set_group_policy frozen-renderer 10 10 128M 384M 128
      set_group_policy discardable-renderer 5 5 64M 128M 64
      set_group_freeze frozen-renderer 1
      ;;
    critical)
      set_group_policy background-renderer 25 25 192M 512M 128
      set_group_policy frozen-renderer 5 5 64M 192M 64
      set_group_policy discardable-renderer 1 1 32M 64M 32
      set_group_freeze frozen-renderer 1
      ;;
    *)
      record_runtime_state ALPENGLOW_PRESSURE_POLICY_APPLIED 0
      return 0
      ;;
  esac
  record_runtime_state ALPENGLOW_PRESSURE_POLICY_APPLIED 1
}

run_once() {
  if [ -r /proc/pressure/cpu ]; then
    record_runtime_state ALPENGLOW_PRESSURE_PSI_CPU active
  else
    record_runtime_state ALPENGLOW_PRESSURE_PSI_CPU unavailable
  fi
  if [ -r /proc/pressure/memory ]; then
    record_runtime_state ALPENGLOW_PRESSURE_PSI_MEMORY active
  else
    record_runtime_state ALPENGLOW_PRESSURE_PSI_MEMORY unavailable
  fi
  if [ -r /proc/pressure/io ]; then
    record_runtime_state ALPENGLOW_PRESSURE_PSI_IO active
  else
    record_runtime_state ALPENGLOW_PRESSURE_PSI_IO unavailable
  fi
  level="$(classify_pressure)"
  apply_pressure_level "${level}"
}

if [ "${ALPENGLOW_PRESSURE_ONESHOT}" = "1" ]; then
  run_once
  exit 0
fi

while :; do
  run_once
  sleep "${ALPENGLOW_PRESSURE_INTERVAL_SECONDS}"
done

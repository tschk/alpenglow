#!/bin/sh
# Create missing state paths and migrate the old root-owned default layout.

ensure_state_dir() {
  dir="$1"
  owner="$2"
  mode="$3"
  marker="${marker_root}/$4"
  if [ -L "${dir}" ]; then
    echo "state directory is a symlink: ${dir}" >&2
    return 1
  fi
  if [ -e "${dir}" ] && [ ! -d "${dir}" ]; then
    echo "state directory is not a directory: ${dir}" >&2
    return 1
  fi
  if [ -e "${marker}" ] || [ -L "${marker}" ]; then
    if [ -L "${marker}" ] || [ ! -d "${marker}" ]; then
      echo "invalid state migration marker: ${marker}" >&2
      return 1
    fi
  elif [ -d "${dir}" ]; then
    # The previous mount script created these private paths as root:root 0755.
    # Update only that known layout; keep all other existing settings and data.
    if [ "${owner}" = 770:770 ]; then
      if ! legacy_dir="$(find "${dir}" -prune -user 0 -group 0 -perm 0755 -print)"; then
        echo "state directory inspection failed: ${dir}" >&2
        return 1
      fi
      if [ "${legacy_dir}" != "${dir}" ]; then
        return 0
      fi
    else
      return 0
    fi
  fi
  # The root-only marker precedes any metadata change or new path creation.
  if [ ! -d "${marker}" ] && ! mkdir -m 0700 "${marker}"; then
    echo "state migration marker creation failed: ${marker}" >&2
    return 1
  fi
  if [ ! -d "${dir}" ] && ! mkdir -m "${mode}" "${dir}"; then
    echo "state directory creation failed: ${dir}" >&2
    return 1
  fi
  if ! chmod "${mode}" "${dir}" || ! chown "${owner}" "${dir}" || ! rmdir "${marker}"; then
    echo "state directory permissions failed: ${dir}" >&2
    return 1
  fi
}

prepare_state_markers() {
  marker_root="$1/.alpenglow-state-migrations"
  if [ -L "${marker_root}" ] || { [ -e "${marker_root}" ] && [ ! -d "${marker_root}" ]; }; then
    echo "invalid state migration marker directory: ${marker_root}" >&2
    return 1
  fi
  if [ ! -d "${marker_root}" ]; then
    if ! mkdir -m 0700 "${marker_root}" || ! chown 0:0 "${marker_root}" || ! chmod 0700 "${marker_root}"; then
      echo "state migration marker directory creation failed: ${marker_root}" >&2
      return 1
    fi
  fi
  if ! marker_dir="$(find "${marker_root}" -prune -user 0 -group 0 -perm 0700 -print)" || [ "${marker_dir}" != "${marker_root}" ]; then
    echo "state migration marker directory is not root-owned and private: ${marker_root}" >&2
    return 1
  fi
}

bind_state_dir() {
  if ! mount --bind "$1" "$2"; then
    echo "state bind mount failed: $1 -> $2" >&2
    return 1
  fi
}

setup_state_paths() {
  state_root="$1"
  target_root="$2"
  prepare_state_markers "${state_root}" || return 1

  # Parents first, so each newly created path receives its intended mode.
  ensure_state_dir "${state_root}/home" 0:0 0755 home || return 1
  ensure_state_dir "${state_root}/var" 0:0 0755 var || return 1
  ensure_state_dir "${state_root}/var/lib" 0:0 0755 var_lib || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow" 0:0 0755 var_lib_alpenglow || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/browser" 770:770 0700 browser || return 1
  for dir in profiles cache downloads state logs terminal; do
    ensure_state_dir "${state_root}/var/lib/alpenglow/browser/${dir}" 770:770 0700 "browser_${dir}" || return 1
  done
  ensure_state_dir "${state_root}/var/lib/alpenglow/files" 770:770 0700 files || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/system" 770:770 0700 system || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/system/plugins" 770:770 0700 system_plugins || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/oil" 0:0 0755 oil || return 1
  ensure_state_dir "${state_root}/var/cache" 0:0 0755 var_cache || return 1
  ensure_state_dir "${state_root}/var/cache/alpenglow" 770:770 0700 alpenglow_cache || return 1
  ensure_state_dir "${state_root}/var/log" 0:0 0755 var_log || return 1
  ensure_state_dir "${state_root}/var/log/alpenglow" 0:0 0700 alpenglow_log || return 1

  # All four binds are required for persistent state to be ready.
  bind_state_dir "${state_root}/home" "${target_root}/home" || return 1
  bind_state_dir "${state_root}/var/lib/alpenglow" "${target_root}/var/lib/alpenglow" || return 1
  bind_state_dir "${state_root}/var/cache/alpenglow" "${target_root}/var/cache/alpenglow" || return 1
  bind_state_dir "${state_root}/var/log/alpenglow" "${target_root}/var/log/alpenglow" || return 1
}

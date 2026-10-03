#!/bin/sh
# Create missing state paths and migrate the old root-owned default layout.

ensure_state_dir() {
  dir="$1"
  owner="$2"
  mode="$3"
  if [ -L "${dir}" ]; then
    echo "state directory is a symlink: ${dir}" >&2
    return 1
  fi
  if [ -d "${dir}" ]; then
    # The previous mount script created these private paths as root:root 0755.
    # Update only that known layout; keep all other existing settings and data.
    if [ "${owner}" = 770:770 ]; then
      if ! legacy_dir="$(find "${dir}" -prune -user 0 -group 0 -perm 0755 -print)"; then
        echo "state directory inspection failed: ${dir}" >&2
        return 1
      fi
      if [ "${legacy_dir}" = "${dir}" ]; then
        if ! chown "${owner}" "${dir}" || ! chmod "${mode}" "${dir}"; then
          echo "legacy state directory migration failed: ${dir}" >&2
          return 1
        fi
      fi
    fi
    return 0
  fi
  if ! mkdir -p "${dir}"; then
    echo "state directory creation failed: ${dir}" >&2
    return 1
  fi
  if ! chown "${owner}" "${dir}" || ! chmod "${mode}" "${dir}"; then
    echo "state directory permissions failed: ${dir}" >&2
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

  # Parents first, so each newly created path receives its intended mode.
  ensure_state_dir "${state_root}/home" 0:0 0755 || return 1
  ensure_state_dir "${state_root}/var" 0:0 0755 || return 1
  ensure_state_dir "${state_root}/var/lib" 0:0 0755 || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow" 0:0 0755 || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/browser" 770:770 0700 || return 1
  for dir in profiles cache downloads state logs terminal; do
    ensure_state_dir "${state_root}/var/lib/alpenglow/browser/${dir}" 770:770 0700 || return 1
  done
  ensure_state_dir "${state_root}/var/lib/alpenglow/files" 770:770 0700 || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/system" 770:770 0700 || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/system/plugins" 770:770 0700 || return 1
  ensure_state_dir "${state_root}/var/lib/alpenglow/oil" 0:0 0755 || return 1
  ensure_state_dir "${state_root}/var/cache" 0:0 0755 || return 1
  ensure_state_dir "${state_root}/var/cache/alpenglow" 770:770 0700 || return 1
  ensure_state_dir "${state_root}/var/log" 0:0 0755 || return 1
  ensure_state_dir "${state_root}/var/log/alpenglow" 0:0 0700 || return 1

  # All four binds are required for persistent state to be ready.
  bind_state_dir "${state_root}/home" "${target_root}/home" || return 1
  bind_state_dir "${state_root}/var/lib/alpenglow" "${target_root}/var/lib/alpenglow" || return 1
  bind_state_dir "${state_root}/var/cache/alpenglow" "${target_root}/var/cache/alpenglow" || return 1
  bind_state_dir "${state_root}/var/log/alpenglow" "${target_root}/var/log/alpenglow" || return 1
}

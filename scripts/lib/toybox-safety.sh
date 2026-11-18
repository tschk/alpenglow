#!/bin/sh

check_toybox_safety() (
  set -f
  binary="$1"
  dir="$(mktemp -d)" || exit 1
  trap 'rm -rf "${dir}"' EXIT
  path="$(CDPATH='' cd -- "$(dirname -- "${binary}")" && pwd)/$(basename -- "${binary}")"
  ln -s "${path}" "${dir}/toybox"
  if applets="$("${dir}/toybox" 2>/dev/null)"; then
    :
  elif command -v qemu-aarch64 >/dev/null 2>&1 && file "${binary}" | grep -q 'aarch64'; then
    applets="$(qemu-aarch64 -0 toybox "${binary}" 2>/dev/null)" || {
      echo "cannot inspect Toybox applets: ${binary}" >&2
      exit 1
    }
  else
    echo "cannot inspect Toybox applets: ${binary}; cross builds require qemu-aarch64" >&2
    exit 1
  fi
  [ -n "${applets}" ] || { echo "empty Toybox applet list: ${binary}" >&2; exit 1; }
  for applet in ${applets}; do
    case "${applet}" in
      passwd|chsh|useradd|userdel|groupadd|groupdel)
        echo "unsafe Toybox account applet '${applet}' in ${binary}: see docs/toybox-account-update-bug.md" >&2
        exit 1
        ;;
    esac
  done
)

#!/bin/sh
set -eu

ROOTFS="${1:-build/alpine/rootfs}"
MAX_PACKAGES="${ALPENGLOW_MAX_RUNTIME_PACKAGES:-84}"
MAX_SIZE_KIB="${ALPENGLOW_MAX_RUNTIME_SIZE_KIB:-380000}"

if [ ! -d "${ROOTFS}" ]; then
  echo "rootfs directory not found: ${ROOTFS}" >&2
  exit 1
fi

world="${ROOTFS}/etc/apk/world"
if [ ! -f "${world}" ]; then
  world="${ROOTFS}/etc/apk/world.alpenglow"
fi
if [ ! -f "${world}" ]; then
  echo "apk world not found under ${ROOTFS}" >&2
  exit 1
fi

packages="$(grep -Ev '^[[:space:]]*(#|$)' "${world}" | wc -l | tr -d ' ')"
if [ "${packages}" -gt "${MAX_PACKAGES}" ]; then
  echo "runtime package count ${packages} exceeds ${MAX_PACKAGES}" >&2
  exit 1
fi

if grep -Eq '^(build-base|cargo|rust|rustup|git|bash|nodejs|bun|npm|yarn|pnpm|python3|py3-pip)$' "${world}"; then
  echo "runtime world contains developer packages" >&2
  exit 1
fi

if grep -Eq '^(xwayland|gcompat|font-noto|bluez|cups|avahi|wpa_supplicant)$' "${world}"; then
  echo "runtime world contains stripped appliance packages" >&2
  exit 1
fi

if [ -x "${ROOTFS}/sbin/apk" ] && command -v chroot >/dev/null 2>&1; then
  size_kib="$(chroot "${ROOTFS}" /sbin/apk info -s 2>/dev/null | awk '/installed size/ {sum += $1} END {print sum + 0}')"
  if [ "${size_kib}" -gt "${MAX_SIZE_KIB}" ]; then
    echo "runtime apk installed size ${size_kib} KiB exceeds ${MAX_SIZE_KIB} KiB" >&2
    exit 1
  fi
fi

printf 'runtime package budget: %s packages\n' "${packages}"

#!/bin/sh
# Fail a release build whose composed rootfs does not honour its edition.
# Usage: check-release-rootfs.sh <rootfs>   (edition env from edition-resolve.sh)
# Dev boots stay best effort; only release images must carry what the
# edition's world file promises.
set -eu

ROOTFS="${1:?rootfs directory}"
ROOT_DIR="${ROOT_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}"
[ -n "${FAST:-}" ] && [ -n "${WORLD_FILE:-}" ] || . "${ROOT_DIR}/scripts/edition-resolve.sh"
WORLD="${ROOT_DIR}/system/backends/appliance/${WORLD_FILE}"
problems=""
problem() { problems="${problems}  - $1
"; }
world_has() { grep -qx "$1" "${WORLD}"; }
boot_has() {
  [ -e "${ROOTFS}/etc/dinit.d/boot.d/$1" ] || [ -L "${ROOTFS}/etc/dinit.d/boot.d/$1" ] ||
    grep -Eq "^(depends-on|waits-for) = $1\$" "${ROOTFS}/etc/dinit.d/boot" 2>/dev/null
}
have_bin() { [ -x "${ROOTFS}/usr/sbin/$1" ] || [ -x "${ROOTFS}/usr/bin/$1" ]; }

[ -d "${ROOTFS}" ] || { echo "check-release-rootfs: no rootfs at ${ROOTFS}" >&2; exit 1; }
[ -e "${ROOTFS}/init" ] || problem "/init missing"
[ -f "${ROOTFS}/etc/dinit.d/boot" ] || problem "dinit boot service missing"

# No account may have an empty password field.
if [ -f "${ROOTFS}/etc/shadow" ]; then
  empty="$(awk -F: '$2 == "" { print $1 }' "${ROOTFS}/etc/shadow")"
  [ -z "${empty}" ] || problem "empty password in /etc/shadow for: ${empty}"
else
  problem "/etc/shadow missing"
fi

if [ "${FAST}" = "1" ]; then
  # Zero overhead: nothing optional may start.
  for svc in dropbear chronyd dnsmasq networking state-mount; do
    boot_has "${svc}" && problem "fast must not start ${svc}"
  done
else
  for pair in dropbear:dropbear chrony:chronyd dnsmasq:dnsmasq; do
    pkg="${pair%%:*}"
    svc="${pair#*:}"
    world_has "${pkg}" || continue
    have_bin "${svc}" || problem "${WORLD_FILE} lists ${pkg} but ${svc} is not in the image"
    boot_has "${svc}" || problem "${svc} is not started at boot"
  done
  if world_has sdhcp; then
    have_bin sdhcp || problem "${WORLD_FILE} lists sdhcp but it is not in the image"
    boot_has networking || problem "networking is not started at boot"
  fi
  boot_has state-mount || problem "/state is never mounted"
  [ -x "${ROOTFS}/usr/local/bin/oil" ] || problem "oil is not in the image"
  if [ "${KERNEL_POLICY}" != "none" ]; then
    [ -f "${ROOTFS}/etc/alpenglow/kernel-policy.json" ] || problem "kernel policy ${KERNEL_POLICY} not shipped"
    boot_has alpenglow-kernel-policy || problem "kernel policy is never applied"
  fi
fi

if [ -n "${problems}" ]; then
  printf 'check-release-rootfs: %s image does not match editions.toml:\n%s' "${ALPENGLOW_SKU}" "${problems}" >&2
  exit 1
fi
printf 'check-release-rootfs: %s ok\n' "${ALPENGLOW_SKU}"

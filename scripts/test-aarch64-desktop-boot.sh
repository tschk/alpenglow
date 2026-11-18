#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BUILDER="${ROOT_DIR}/scripts/build-aarch64-desktop.sh"

extract() {
  awk -v target="$1" '
    index($0, "cat > \"${ROOTFS}/" target "\" <<\047EOF\047") { found=1; next }
    found && $0 == "EOF" { exit }
    found { print }
  ' "${BUILDER}"
}

fail() { echo "FAIL: $*" >&2; exit 1; }
grep -Eq 'PACKAGES="[^"]* eudev ' "${BUILDER}" || fail 'eudev package missing'
grep -Eq 'PACKAGES="[^"]* eudev-hwids ' "${BUILDER}" || fail 'eudev hardware database missing'
init="$(extract init)"
printf '%s\n' "${init}" | awk '
  /mount -t devtmpfs/ { dev=NR }
  /mkdir -p \/dev\/pts/ { pts=NR }
  /mount -t devpts/ { mountpts=NR }
  /mkdir -p \/dev\/shm/ { shm=NR }
  /mount -t tmpfs .*\/dev\/shm/ { mountshm=NR }
  END { exit !(dev && dev < pts && pts < mountpts && dev < shm && shm < mountshm) }
' || fail 'devpts or shared memory setup missing or ordered incorrectly'
udevd="$(extract etc/dinit.d/udevd)"
coldplug="$(extract etc/dinit.d/udev-coldplug)"
desktop="$(extract etc/dinit.d/desktop)"
printf '%s\n' "${udevd}" | grep -q '^command = /sbin/udevd$' || fail 'udevd is not supervised in foreground'
printf '%s\n' "${coldplug}" | grep -q '^depends-on = udevd$' || fail 'coldplug does not depend on udevd'
printf '%s\n' "${desktop}" | grep -q '^depends-on = udev-coldplug$' || fail 'desktop does not wait for coldplug'
coldplug_script="$(extract usr/local/bin/udev-coldplug)"
printf '%s\n' "${coldplug_script}" | grep -q 'udevadm trigger' || fail 'coldplug trigger missing'
printf '%s\n' "${coldplug_script}" | grep -q 'udevadm settle' || fail 'coldplug settle missing'
echo 'aarch64 desktop boot contract: OK'

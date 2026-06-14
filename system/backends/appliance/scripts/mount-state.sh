#!/bin/sh
# Mount persistent state partition for diskless mode.
# State device is discovered by label or UUID.
set -eu

STATE_LABEL="${STATE_LABEL:-alpenglow-state}"
STATE_MOUNT="${STATE_MOUNT:-/state}"

mkdir -p "${STATE_MOUNT}"

# Try by label first
if [ -b "/dev/disk/by-label/${STATE_LABEL}" ]; then
  mount -t ext4 -o rw,nosuid,nodev "/dev/disk/by-label/${STATE_LABEL}" "${STATE_MOUNT}"
  exit 0
fi

# Try kernel arg
for arg in $(cat /proc/cmdline); do
  case "${arg}" in
    alpenglow.state=*)
      dev="${arg#alpenglow.state=}"
      mount -t ext4 -o rw,nosuid,nodev "${dev}" "${STATE_MOUNT}" 2>/dev/null && exit 0
      ;;
  esac
done

# No state device — operate in pure diskless mode (no persistence)
echo "No state device found — running diskless without persistence" >&2
exit 0

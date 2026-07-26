# Alpenglow mount-state script
# Mounts persistent state partition by label or kernel arg.
#
# Encrypted /state (optional LUKS path):
#   alpenglow.state.encrypted=1  — require LUKS open before bcachefs mount
#   alpenglow.state.key=/path    — optional LUKS keyfile (prompt if omitted)
# Auto-detect: if the resolved block device is crypto_LUKS, luksOpen first.
# Default boot stays unencrypted; LUKS is only used when flagged or detected.
set -eu

STATE_DEV=""
STATE_ENCRYPTED=""
STATE_KEY=""
for arg in $(cat /proc/cmdline 2>/dev/null); do
  case "${arg}" in
    alpenglow.state=*) STATE_DEV="${arg#alpenglow.state=}" ;;
    alpenglow.state.encrypted=*) STATE_ENCRYPTED="${arg#alpenglow.state.encrypted=}" ;;
    alpenglow.state.key=*) STATE_KEY="${arg#alpenglow.state.key=}" ;;
  esac
done

state_block_dev() {
  spec="$1"
  case "${spec}" in
    LABEL=*) blkid -L "${spec#LABEL=}" 2>/dev/null || true ;;
    /dev/*) echo "${spec}" ;;
    *) echo "${spec}" ;;
  esac
}

state_is_luks() {
  dev="$1"
  [ -n "${dev}" ] && [ "$(blkid -o value -s TYPE "${dev}" 2>/dev/null)" = "crypto_LUKS" ]
}

open_luks_state() {
  spec="$1"
  dev="$(state_block_dev "${spec}")"
  if [ -z "${dev}" ]; then
    echo "state device not found: ${spec}" >&2
    return 1
  fi

  if [ -e /dev/mapper/alpenglow-state ]; then
    echo /dev/mapper/alpenglow-state
    return 0
  fi

  need_open=0
  if [ "${STATE_ENCRYPTED}" = "1" ]; then
    need_open=1
  elif state_is_luks "${dev}"; then
    need_open=1
  fi

  if [ "${need_open}" -eq 0 ]; then
    echo "${spec}"
    return 0
  fi

  if ! state_is_luks "${dev}"; then
    echo "alpenglow.state.encrypted=1 but device is not LUKS: ${dev}" >&2
    return 1
  fi

  if ! command -v cryptsetup >/dev/null 2>&1; then
    echo "LUKS state device requires cryptsetup" >&2
    return 1
  fi

  modprobe dm-crypt 2>/dev/null || true
  if [ -n "${STATE_KEY}" ] && [ -r "${STATE_KEY}" ]; then
    cryptsetup luksOpen "${dev}" alpenglow-state --key-file "${STATE_KEY}" || return 1
  else
    cryptsetup luksOpen "${dev}" alpenglow-state || return 1
  fi
  echo /dev/mapper/alpenglow-state
}

if ! grep -q ' /state ' /proc/mounts 2>/dev/null; then
  if [ -n "${STATE_DEV}" ]; then
    mount_spec="${STATE_DEV}"
  else
    mount_spec="LABEL=alpenglow-state"
  fi
  mount_dev="$(open_luks_state "${mount_spec}")" || exit 1
  mount -t bcachefs -o rw,nosuid,nodev "${mount_dev}" /state 2>/dev/null || { echo "bcachefs state mount failed: ${mount_dev}" >&2; exit 1; }
fi

# Create state directories if they don't exist
for dir in \
  /state/home \
  /state/var/lib/alpenglow/browser/profiles \
  /state/var/lib/alpenglow/browser/cache \
  /state/var/lib/alpenglow/browser/downloads \
  /state/var/lib/alpenglow/browser/state \
  /state/var/lib/alpenglow/browser/logs \
  /state/var/lib/alpenglow/browser/terminal \
  /state/var/lib/alpenglow/files \
  /state/var/lib/alpenglow/system \
  /state/var/lib/alpenglow/system/plugins \
  /state/var/lib/alpenglow/oil \
  /state/var/cache/alpenglow \
  /state/var/log/alpenglow; do
  mkdir -p "${dir}" 2>/dev/null || true
done

# Bind mount state directories into live filesystem
mount --bind /state/home /home 2>/dev/null || true
mount --bind /state/var/lib/alpenglow /var/lib/alpenglow 2>/dev/null || true
mount --bind /state/var/cache/alpenglow /var/cache/alpenglow 2>/dev/null || true
mount --bind /state/var/log/alpenglow /var/log/alpenglow 2>/dev/null || true

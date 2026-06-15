# Alpenglow mount-state script
# Mounts persistent state partition by label or kernel arg
set -eu

STATE_DEV=""
for arg in $(cat /proc/cmdline 2>/dev/null); do
  case "${arg}" in
    alpenglow.state=*) STATE_DEV="${arg#alpenglow.state=}" ;;
  esac
done

if [ -n "${STATE_DEV}" ]; then
  mount -t ext4 -o rw,nosuid,nodev "${STATE_DEV}" /state 2>/dev/null || true
else
  mount -t ext4 -o rw,nosuid,nodev LABEL=alpenglow-state /state 2>/dev/null || true
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

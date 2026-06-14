export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [ -z "${ALPENGLOW_TOKEN:-}" ]; then
  TOKEN_FILE="/var/lib/alpenglow/system/api-token"
  if [ ! -f "${TOKEN_FILE}" ] && [ -w "$(dirname "${TOKEN_FILE}")" ]; then
    head -c 32 /dev/urandom | base64 | tr -d '+/=' > "${TOKEN_FILE}" || true
    chmod 600 "${TOKEN_FILE}" 2>/dev/null || true
  fi
  if [ -f "${TOKEN_FILE}" ]; then
    export ALPENGLOW_TOKEN="$(cat "${TOKEN_FILE}")"
  else
    export ALPENGLOW_TOKEN="$(head -c 32 /dev/urandom | base64 | tr -d '+/=')"
  fi
else
  export ALPENGLOW_TOKEN="${ALPENGLOW_TOKEN}"
fi
export ALPENGLOW_UI_URL="${ALPENGLOW_UI_URL:-file:///opt/alpenglow/ui/index.html}"
export ALPENGLOW_SYSTEM_CONFIG="${ALPENGLOW_SYSTEM_CONFIG:-/etc/alpenglow/system.json}"
export ALPENGLOW_GENERATION_FILE="${ALPENGLOW_GENERATION_FILE:-/etc/alpenglow/generation.json}"
export ALPENGLOW_MARK_GOOD_HOOK="${ALPENGLOW_MARK_GOOD_HOOK:-/usr/local/bin/alpenglow-generation-mark-good}"
export ALPENGLOW_UPDATE_STATE="${ALPENGLOW_UPDATE_STATE:-/var/lib/alpenglow/system/update-state.json}"

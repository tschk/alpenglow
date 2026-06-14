export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [ -z "${SOL_TOKEN:-}" ]; then
  TOKEN_FILE="/var/lib/soliloquy/system/api-token"
  if [ ! -f "${TOKEN_FILE}" ] && [ -w "$(dirname "${TOKEN_FILE}")" ]; then
    head -c 32 /dev/urandom | base64 | tr -d '+/=' > "${TOKEN_FILE}" || true
    chmod 600 "${TOKEN_FILE}" 2>/dev/null || true
  fi
  if [ -f "${TOKEN_FILE}" ]; then
    export SOL_TOKEN="$(cat "${TOKEN_FILE}")"
  else
    export SOL_TOKEN="$(head -c 32 /dev/urandom | base64 | tr -d '+/=')"
  fi
else
  export SOL_TOKEN="${SOL_TOKEN}"
fi
export SOL_UI_URL="${SOL_UI_URL:-file:///opt/sol/ui/index.html}"
export SOLILOQUY_SYSTEM_CONFIG="${SOLILOQUY_SYSTEM_CONFIG:-/etc/soliloquy/system.json}"
export SOLILOQUY_GENERATION_FILE="${SOLILOQUY_GENERATION_FILE:-/etc/soliloquy/generation.json}"
export SOLILOQUY_MARK_GOOD_HOOK="${SOLILOQUY_MARK_GOOD_HOOK:-/usr/local/bin/soliloquy-generation-mark-good}"
export SOLILOQUY_UPDATE_STATE="${SOLILOQUY_UPDATE_STATE:-/var/lib/soliloquy/system/update-state.json}"

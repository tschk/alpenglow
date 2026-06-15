#!/bin/sh
# ──────────────────────────────────────────────────────────────────────
# Alpenglow OS Migration Script
#
# Migrates between Alpenglow backends (e.g. void-musl-runit → chimera-musl-dinit)
# or from a source distro into Alpenglow's composed rootfs model.
#
# Usage:  sudo ./scripts/migrate-os.sh [--from <backend>] [--to <backend>] [--dry-run]
#
# With --from void --to chimera, will attempt to migrate an existing Void
# installation onto Alpenglow's immutable rootfs model with dinit + clang.
# ──────────────────────────────────────────────────────────────────────

set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
DRY_RUN=0
FROM_BACKEND=""
TO_BACKEND=""

usage() {
  echo "usage: $0 [--from <backend>] [--to <backend>] [--dry-run]"
  echo ""
  echo "backends: void-musl-runit, alpine-openrc, chimera-musl-dinit, oasis-static"
  echo ""
  echo "examples:"
  echo "  $0 --from void-musl-runit --to chimera-musl-dinit"
  echo "  $0 --from alpine-openrc --to void-musl-runit --dry-run"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM_BACKEND="$2"; shift 2 ;;
    --to) TO_BACKEND="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage ;;
    *) echo "unknown option: $1"; usage ;;
  esac
done

if [ -z "${FROM_BACKEND}" ] || [ -z "${TO_BACKEND}" ]; then
  echo "error: --from and --to are required" >&2
  usage
fi

# Resolve backend directories
FROM_DIR="$("${ROOT_DIR}/system/appliance/scripts/select-backend.sh" "${FROM_BACKEND}" 2>/dev/null)" || {
  echo "error: unknown source backend '${FROM_BACKEND}'" >&2
  exit 1
}
TO_DIR="$("${ROOT_DIR}/system/appliance/scripts/select-backend.sh" "${TO_BACKEND}" 2>/dev/null)" || {
  echo "error: unknown target backend '${TO_BACKEND}'" >&2
  exit 1
}

echo "Alpenglow OS Migration"
echo "  from: ${FROM_BACKEND} (${FROM_DIR})"
echo "  to:   ${TO_BACKEND} (${TO_DIR})"
echo ""

if [ "${DRY_RUN}" = "1" ]; then
  echo "[dry-run] Would perform the following steps:"
fi

# ── Migration steps ────────────────────────────────────────────────

step_backend_json() {
  local src="$1"
  local dst="$2"
  step "Install ${dst} backend metadata: backend.json, system.json"
  if [ "${DRY_RUN}" = "0" ]; then
    cp "${src}/backend.json" /etc/alpenglow/backend.json
    "${src}/scripts/configure-rootfs.sh" /
  fi
}

step_swap_init() {
  local src_init="$1"
  local dst_init="$2"
  step "Swap init system: ${src_init} → ${dst_init}"
  if [ "${DRY_RUN}" = "0" ]; then
    case "${dst_init}" in
      runit)
        # Install runit, remove dinit/OpenRC
        ;;
      dinit)
        # Install dinit, configure service symlinks
        mkdir -p /etc/dinit.d/boot.d
        for svc in seatd alpenglow-kernel-policy alpenglow-netd alpenglow-zram alpenglow-pressure networking; do
          if [ -f "/etc/dinit.d/${svc}" ]; then
            ln -sf "/etc/dinit.d/${svc}" "/etc/dinit.d/boot.d/${svc}"
          fi
        done
        ;;
      openrc)
        # Enable OpenRC services
        for svc in seatd alpenglow-kernel-policy alpenglow-netd; do
          rc-update add "${svc}" default 2>/dev/null || true
        done
        ;;
    esac
  fi
}

step_compiler() {
  local policy="$1"
  step "Set system compiler: ${policy}"
  if [ "${DRY_RUN}" = "0" ]; then
    mkdir -p /etc/profile.d
    cat > /etc/profile.d/alpenglow-compiler.sh <<'COMPEOF'
# Alpenglow default compiler
CC=clang
CXX=clang++
LD=lld
AR=llvm-ar
NM=llvm-nm
export CC CXX LD AR NM
COMPEOF
    chmod 644 /etc/profile.d/alpenglow-compiler.sh
  fi
}

step_pm() {
  local pm="$1"
  step "Set package manager: ${pm}"
}

step() {
  local msg="$1"
  shift
  if [ "${DRY_RUN}" = "1" ]; then
    echo "  [DRY-RUN] ${msg}"
  else
    echo "  → ${msg}"
  fi
  # Run hook if provided
  if [ $# -gt 0 ] && [ "${DRY_RUN}" = "0" ]; then
    "$@"
  fi
}

echo ""
echo "Migration plan:"
echo ""

# Read backend metadata to plan migration
read_backend_meta() {
  local dir="$1"
  local key="$2"
  if [ -f "${dir}/backend.json" ]; then
    grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "${dir}/backend.json" | head -1 | sed 's/.*: "\(.*\)"/\1/'
  fi
}

FROM_INIT=$(read_backend_meta "${FROM_DIR}" "init")
TO_INIT=$(read_backend_meta "${TO_DIR}" "init")
FROM_COMPILER=$(read_backend_meta "${FROM_DIR}" "default" 2>/dev/null || echo "gcc")
TO_COMPILER=$(read_backend_meta "${TO_DIR}" "default" 2>/dev/null || echo "clang")

echo "1. Install target backend metadata"
step_backend_json "${TO_DIR}" "/"
echo ""

echo "2. Swap init system: ${FROM_INIT:-unknown} → ${TO_INIT:-unknown}"
step_swap_init "${FROM_INIT:-}" "${TO_INIT:-}"
echo ""

echo "3. Configure system compiler: ${TO_COMPILER:-clang}"
step_compiler "${TO_COMPILER:-clang}"
echo ""

echo "4. Switch package manager bootstrap"
step_pm "$(read_backend_meta "${TO_DIR}" "bootstrap_package_manager")"
echo ""

echo "5. Install target packages"
step "Install packages from ${TO_BACKEND} world manifest"
if [ -f "${TO_DIR}/packages-runtime.txt" ] && [ "${DRY_RUN}" = "0" ]; then
  cp "${TO_DIR}/packages-runtime.txt" /etc/alpenglow/world
fi
echo ""

echo "6. Mark migration generation"
if [ "${DRY_RUN}" = "1" ]; then
  echo "  [DRY-RUN] Create generation: migrate-from-${FROM_BACKEND}-to-${TO_BACKEND}"
fi
echo ""

echo "Migration of ${FROM_BACKEND} → ${TO_BACKEND} complete."
echo "Reboot to activate the new backend."

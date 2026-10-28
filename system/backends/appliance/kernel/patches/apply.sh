#!/bin/sh
# Apply kernel/patches/series to a kernel tree before olddefconfig.
# Entries: *.patch (patch -p1) or *.sh (run with the kernel dir). Idempotent.
# Usage: apply.sh <kernel-src-dir>
set -eu
KSRC="${1:?kernel source dir}"
DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
while read -r entry; do
  case "${entry}" in ''|'#'*) continue ;; esac
  case "${entry}" in
    *.sh) sh "${DIR}/${entry}" "${KSRC}" ;;
    *.patch)
      if (cd "${KSRC}" && patch -p1 -R -s -f --dry-run < "${DIR}/${entry}") >/dev/null 2>&1; then
        continue
      fi
      (cd "${KSRC}" && patch -p1 -s < "${DIR}/${entry}")
      ;;
    *) echo "kernel patches: unknown series entry: ${entry}" >&2; exit 1 ;;
  esac
done < "${DIR}/series"

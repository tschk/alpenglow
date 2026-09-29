#!/bin/sh
# Apply a kernel config fragment with scripts/config, which overrides symbols
# that defconfig already set. Appending to .config and running olddefconfig
# keeps the earlier value.
# Usage: apply-fragment.sh <fragment>   (run from the kernel source tree)
set -eu

fragment="${1:?fragment}"
args=""
while IFS= read -r line; do
  case "$line" in
    \#*|"") continue ;;
  esac
  sym="${line%%=*}"
  sym="${sym#CONFIG_}"
  val="${line#*=}"
  case "$val" in
    y) args="$args --enable $sym" ;;
    n) args="$args --disable $sym" ;;
    m) args="$args --module $sym" ;;
  esac
done < "$fragment"

# shellcheck disable=SC2086
./scripts/config $args

#!/bin/bash

# Filter out GNU ld specific options that are not supported by lld or GCC ld
args=()

sysroot="/tmp/x86-64--glibc--stable-2024.02-1/x86_64-buildroot-linux-gnu/sysroot"

for arg in "$@"; do
  case $arg in
    --as-needed|--eh-frame-hdr|-z,*|--gc-sections|--strip-debug|-Bstatic|-Bdynamic|-pie|-nodefaultlibs)
      # Skip these GNU ld options not supported by lld
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

# Use GCC ld for linking
exec /tmp/x86-64--glibc--stable-2024.02-1/x86_64-buildroot-linux-gnu/bin/ld --sysroot="$sysroot" "${args[@]}"
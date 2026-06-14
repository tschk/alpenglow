#!/bin/bash

# Wrapper for zig cc to fix target names and -L paths

sysroot="/tmp/x86-64--glibc--stable-2024.02-1/x86_64-buildroot-linux-gnu/sysroot"

args=()
i=0
while [ $i -lt $# ]; do
  arg="${!i}"
  ((i++))
  if [[ $arg == --target=x86_64-unknown-linux-gnu ]]; then
    args+=("--target=x86_64-linux-gnu")
  elif [[ $arg == --target=x86_64-unknown-linux-musl ]]; then
    args+=("--target=x86_64-linux-musl")
  elif [[ $arg == -L && $i -lt $# ]]; then
    next_arg="${!i}"
    ((i++))
    if [[ $next_arg == /* ]]; then
      # Check if it starts with sysroot
      if [[ $next_arg == $sysroot/* ]]; then
        # Make relative to sysroot
        relative_path="${next_arg#$sysroot/}"
        args+=("-L$relative_path")
      else
        # Convert absolute -L paths to relative paths (assuming they are in sysroot)
        relative_path="${next_arg:1}"
        args+=("-L$relative_path")
      fi
    else
      args+=("$arg" "$next_arg")
    fi
  elif [[ $arg =~ ^-L/ ]]; then
    # Handle -L/path (though usually -L and path are separate)
    path="${arg:3}"
    if [[ $path == $sysroot/* ]]; then
      relative_path="${path#$sysroot/}"
      args+=("-L$relative_path")
    else
      relative_path="${path:1}"
      args+=("-L$relative_path")
    fi
  else
    args+=("$arg")
  fi
done

zig cc --sysroot="$sysroot" "${args[@]}"
#!/bin/bash

# Linker wrapper for clang with lld, dynamic linking

exec clang -fuse-ld=lld --target=x86_64-linux-gnu --sysroot=/tmp/x86-64-sysroot/x86_64-buildroot-linux-gnu/sysroot "$@"
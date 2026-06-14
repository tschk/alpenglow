#!/bin/bash
exec clang --target=x86_64-linux-gnu --sysroot=/tmp/x86-64--glibc--stable-2024.02-1/x86_64-buildroot-linux-gnu/sysroot "$@"
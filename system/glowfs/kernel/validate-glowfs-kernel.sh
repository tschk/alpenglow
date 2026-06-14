#!/bin/sh
set -eu

GLOWFS_KERNEL_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

fail() {
  printf 'validate-glowfs-kernel: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_contains() {
  file="$1"
  pattern="$2"
  if ! grep -Eq "${pattern}" "${file}"; then
    fail "${file} does not match ${pattern}"
  fi
}

assert_file "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c"
assert_file "${GLOWFS_KERNEL_DIR}/glowfs_core.rs"
assert_file "${GLOWFS_KERNEL_DIR}/glowfs_format.h"
assert_file "${GLOWFS_KERNEL_DIR}/Kbuild"
assert_file "${GLOWFS_KERNEL_DIR}/Makefile"

assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'register_filesystem'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'mount_bdev'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_lookup'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_iterate_shared'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'generic_file_read_iter'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_read_folio'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_readahead'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_write_begin'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_write_end'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_writepage'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'generic_file_mmap'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'generic_file_fsync'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'generic_file_write_iter'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'filemap_splice_read'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'filemap_dirty_folio'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'GLOWFS_FLAG_MUTABLE'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'allocation_lock'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_align8'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_write_header_image_size'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_write_disk_entry'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_load_v2_superblock'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'GLOWFS_FLAG_V2'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'GLOWFS_KIND_SYMLINK'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_get_link'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'iget_locked'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'glowfs_rust_validate_header'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" '__weak int glowfs_rust_validate_header'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_vfs.c" 'MODULE_LICENSE\("GPL"\)'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_core.rs" '#!\[no_std\]'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_core.rs" 'extern "C" fn glowfs_rust_validate_header'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_format.h" 'GLWFSV01'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_format.h" 'GLWFSV02'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_format.h" 'struct glowfs_v2_superblock'
assert_contains "${GLOWFS_KERNEL_DIR}/glowfs_format.h" 'GLOWFS_KIND_SYMLINK'
assert_contains "${GLOWFS_KERNEL_DIR}/Kbuild" 'glowfs_vfs.o'

if [ -n "${KERNEL_SRC:-}" ]; then
  [ -d "${KERNEL_SRC}" ] || fail "KERNEL_SRC does not exist: ${KERNEL_SRC}"
  make -C "${KERNEL_SRC}" M="${GLOWFS_KERNEL_DIR}" modules
fi

printf 'validate-glowfs-kernel: ok\n'

#!/bin/sh
set -eu

SOLFS_KERNEL_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

fail() {
  printf 'validate-solfs-kernel: %s\n' "$1" >&2
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

assert_file "${SOLFS_KERNEL_DIR}/solfs_vfs.c"
assert_file "${SOLFS_KERNEL_DIR}/solfs_core.rs"
assert_file "${SOLFS_KERNEL_DIR}/solfs_format.h"
assert_file "${SOLFS_KERNEL_DIR}/Kbuild"
assert_file "${SOLFS_KERNEL_DIR}/Makefile"

assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'register_filesystem'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'mount_bdev'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_lookup'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_iterate_shared'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'generic_file_read_iter'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_read_folio'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_readahead'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_write_begin'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_write_end'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_writepage'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'generic_file_mmap'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'generic_file_fsync'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'generic_file_write_iter'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'filemap_splice_read'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'filemap_dirty_folio'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'SOLFS_FLAG_MUTABLE'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'allocation_lock'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_align8'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_write_header_image_size'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_write_disk_entry'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_load_v2_superblock'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'SOLFS_FLAG_V2'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'SOLFS_KIND_SYMLINK'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_get_link'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'iget_locked'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'solfs_rust_validate_header'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" '__weak int solfs_rust_validate_header'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_vfs.c" 'MODULE_LICENSE\("GPL"\)'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_core.rs" '#!\[no_std\]'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_core.rs" 'extern "C" fn solfs_rust_validate_header'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_format.h" 'SOLFSV01'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_format.h" 'SOLFSV02'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_format.h" 'struct solfs_v2_superblock'
assert_contains "${SOLFS_KERNEL_DIR}/solfs_format.h" 'SOLFS_KIND_SYMLINK'
assert_contains "${SOLFS_KERNEL_DIR}/Kbuild" 'solfs_vfs.o'

if [ -n "${KERNEL_SRC:-}" ]; then
  [ -d "${KERNEL_SRC}" ] || fail "KERNEL_SRC does not exist: ${KERNEL_SRC}"
  make -C "${KERNEL_SRC}" M="${SOLFS_KERNEL_DIR}" modules
fi

printf 'validate-solfs-kernel: ok\n'

#ifndef SOLFS_FORMAT_H
#define SOLFS_FORMAT_H

#include <linux/types.h>

#define SOLFS_MAGIC_STRING "SOLFSV01"
#define SOLFS_SUPER_MAGIC 0x534f4c46
#define SOLFS_VERSION 1
#define SOLFS_HEADER_LEN 56
#define SOLFS_ENTRY_LEN 92
#define SOLFS_KIND_DIR 1
#define SOLFS_KIND_FILE 2
#define SOLFS_KIND_SYMLINK 3
#define SOLFS_FLAG_READONLY 1
#define SOLFS_FLAG_MUTABLE 2
#define SOLFS_FLAG_V2 4
#define SOLFS_V2_MAGIC_STRING "SOLFSV02"
#define SOLFS_V2_VERSION 2
#define SOLFS_V2_BLOCK_SIZE 4096
#define SOLFS_V2_SUPERBLOCK_LEN 96

struct solfs_disk_header {
	u8 magic[8];
	__le32 version;
	__le32 entry_count;
	__le64 entries_offset;
	__le64 names_offset;
	__le64 data_offset;
	__le64 image_size;
	__le64 flags;
} __packed;

struct solfs_disk_entry {
	__le64 inode;
	__le64 parent;
	__le64 name_offset;
	__le32 name_len;
	__le32 kind;
	__le32 mode;
	__le32 uid;
	__le32 gid;
	__le64 data_offset;
	__le64 size;
	u8 digest[32];
} __packed;

struct solfs_v2_superblock {
	u8 magic[8];
	__le32 version;
	__le32 reserved;
	__le64 block_size;
	__le64 bitmap_offset;
	__le64 bitmap_len;
	__le64 extent_table_offset;
	__le64 extent_table_len;
	__le64 journal_offset;
	__le64 journal_len;
	__le64 data_start;
	__le64 total_blocks;
	__le64 free_blocks;
} __packed;

#endif

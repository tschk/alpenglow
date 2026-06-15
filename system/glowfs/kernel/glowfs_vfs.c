#include <linux/buffer_head.h>
#include <linux/fs.h>
#include <linux/highmem.h>
#include <linux/limits.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pagemap.h>
#include <linux/slab.h>
#include <linux/statfs.h>
#include <linux/string.h>
#include <linux/time.h>
#include <linux/uio.h>
#include <linux/version.h>
#include <linux/writeback.h>

#include "glowfs_format.h"

#define GLOWFS_MAX_ENTRIES 65536
#define GLOWFS_MAX_NAMES_SIZE (16 * 1024 * 1024)

int glowfs_rust_validate_header(struct glowfs_disk_header header);

__weak int glowfs_rust_validate_header(struct glowfs_disk_header header)
{
	u32 version = le32_to_cpu(header.version);
	u32 entry_count = le32_to_cpu(header.entry_count);
	u64 entries_offset = le64_to_cpu(header.entries_offset);
	u64 names_offset = le64_to_cpu(header.names_offset);
	u64 data_offset = le64_to_cpu(header.data_offset);
	u64 image_size = le64_to_cpu(header.image_size);
	u64 entries_len;

	if (memcmp(header.magic, GLOWFS_MAGIC_STRING, sizeof(header.magic)))
		return -EINVAL;
	if (version != GLOWFS_VERSION)
		return -EINVAL;
	if (!entry_count)
		return -EINVAL;
	if (check_mul_overflow((u64)entry_count, (u64)GLOWFS_ENTRY_LEN, &entries_len))
		return -EINVAL;
	if (entries_offset != GLOWFS_HEADER_LEN)
		return -EINVAL;
	if (names_offset < entries_offset + entries_len)
		return -EINVAL;
	if (data_offset < names_offset)
		return -EINVAL;
	if (image_size < data_offset)
		return -EINVAL;
	return 0;
}

struct glowfs_entry {
	u64 index;
	u64 inode;
	u64 parent;
	u64 name_offset;
	u64 data_offset;
	u64 size;
	u32 name_len;
	u32 kind;
	u32 mode;
	u32 uid;
	u32 gid;
	u8 digest[32];
	const char *name;
};

struct glowfs_sb_info {
	u32 entry_count;
	u64 names_size;
	u64 flags;
	u64 image_size;
	u64 v2_total_blocks;
	u64 v2_free_blocks;
	struct mutex allocation_lock;
	struct glowfs_entry *entries;
	char *names;
};

static const struct inode_operations glowfs_dir_inode_ops;
static const struct inode_operations glowfs_symlink_inode_ops;
static const struct file_operations glowfs_dir_ops;
static const struct file_operations glowfs_file_ops;
static const struct address_space_operations glowfs_aops;

static struct glowfs_sb_info *glowfs_sbi(struct super_block *sb)
{
	return sb->s_fs_info;
}

static int glowfs_read_bytes(struct super_block *sb, u64 offset, void *dst, size_t len)
{
	u8 *out = dst;
	u64 block;
	u32 block_offset;
	u32 chunk;
	struct buffer_head *bh;

	while (len > 0) {
		block = offset >> sb->s_blocksize_bits;
		block_offset = offset & (sb->s_blocksize - 1);
		chunk = min_t(size_t, len, sb->s_blocksize - block_offset);
		bh = sb_bread(sb, block);
		if (!bh)
			return -EIO;
		memcpy(out, bh->b_data + block_offset, chunk);
		brelse(bh);
		out += chunk;
		offset += chunk;
		len -= chunk;
	}
	return 0;
}

static int glowfs_write_bytes(struct super_block *sb, u64 offset, const void *src, size_t len)
{
	const u8 *in = src;
	u64 block;
	u32 block_offset;
	u32 chunk;
	struct buffer_head *bh;

	while (len > 0) {
		block = offset >> sb->s_blocksize_bits;
		block_offset = offset & (sb->s_blocksize - 1);
		chunk = min_t(size_t, len, sb->s_blocksize - block_offset);
		bh = sb_bread(sb, block);
		if (!bh)
			return -EIO;
		memcpy(bh->b_data + block_offset, in, chunk);
		mark_buffer_dirty(bh);
		brelse(bh);
		in += chunk;
		offset += chunk;
		len -= chunk;
	}
	return 0;
}

static u64 glowfs_align8(u64 value)
{
	return (value + 7) & ~7ULL;
}

static int glowfs_write_header_image_size(struct super_block *sb, u64 image_size)
{
	struct glowfs_disk_header header;
	int ret;

	ret = glowfs_read_bytes(sb, 0, &header, sizeof(header));
	if (ret)
		return ret;
	header.image_size = cpu_to_le64(image_size);
	return glowfs_write_bytes(sb, 0, &header, sizeof(header));
}

static int glowfs_write_disk_entry(struct super_block *sb, struct glowfs_entry *entry)
{
	struct glowfs_disk_entry disk;
	u64 offset = GLOWFS_HEADER_LEN + entry->index * GLOWFS_ENTRY_LEN;

	disk.inode = cpu_to_le64(entry->inode);
	disk.parent = cpu_to_le64(entry->parent);
	disk.name_offset = cpu_to_le64(entry->name_offset);
	disk.name_len = cpu_to_le32(entry->name_len);
	disk.kind = cpu_to_le32(entry->kind);
	disk.mode = cpu_to_le32(entry->mode);
	disk.uid = cpu_to_le32(entry->uid);
	disk.gid = cpu_to_le32(entry->gid);
	disk.data_offset = cpu_to_le64(entry->data_offset);
	disk.size = cpu_to_le64(entry->size);
	memcpy(disk.digest, entry->digest, sizeof(disk.digest));
	return glowfs_write_bytes(sb, offset, &disk, sizeof(disk));
}

static struct glowfs_entry *glowfs_find_inode(struct super_block *sb, u64 inode)
{
	struct glowfs_sb_info *sbi = glowfs_sbi(sb);
	u32 i;

	for (i = 0; i < sbi->entry_count; i++) {
		if (sbi->entries[i].inode == inode)
			return &sbi->entries[i];
	}
	return NULL;
}

static struct glowfs_entry *glowfs_find_child(struct super_block *sb, struct glowfs_entry *parent, const struct qstr *name)
{
	struct glowfs_sb_info *sbi = glowfs_sbi(sb);
	u32 i;

	for (i = 0; i < sbi->entry_count; i++) {
		struct glowfs_entry *entry = &sbi->entries[i];

		if (entry->parent != parent->inode || entry->inode == parent->inode)
			continue;
		if (entry->name_len != name->len)
			continue;
		if (!memcmp(entry->name, name->name, name->len))
			return entry;
	}
	return NULL;
}

static struct inode *glowfs_make_inode(struct super_block *sb, struct glowfs_entry *entry)
{
	struct inode *inode = iget_locked(sb, entry->inode);
	umode_t mode;

	if (!inode)
		return NULL;
	if (!(inode->i_state & I_NEW))
		return inode;

	mode = entry->mode & 0777;
	if (entry->kind == GLOWFS_KIND_DIR)
		mode |= S_IFDIR;
	else if (entry->kind == GLOWFS_KIND_SYMLINK)
		mode |= S_IFLNK;
	else
		mode |= S_IFREG;

	inode->i_ino = entry->inode;
	inode->i_mode = mode;
	inode->i_uid = KUIDT_INIT(entry->uid);
	inode->i_gid = KGIDT_INIT(entry->gid);
	inode->i_size = entry->size;
	inode->i_private = entry;
	inode->i_mapping->a_ops = &glowfs_aops;
	inode_set_atime_to_ts(inode, current_time(inode));
	inode_set_mtime_to_ts(inode, current_time(inode));
	inode_set_ctime_current(inode);

	if (entry->kind == GLOWFS_KIND_DIR) {
		inode->i_op = &glowfs_dir_inode_ops;
		inode->i_fop = &glowfs_dir_ops;
		set_nlink(inode, 2);
	} else if (entry->kind == GLOWFS_KIND_SYMLINK) {
		inode->i_op = &glowfs_symlink_inode_ops;
		set_nlink(inode, 1);
	} else {
		inode->i_fop = &glowfs_file_ops;
		set_nlink(inode, 1);
	}

	unlock_new_inode(inode);
	return inode;
}

static struct dentry *glowfs_lookup(struct inode *dir, struct dentry *dentry, unsigned int flags)
{
	struct glowfs_entry *parent = dir->i_private;
	struct glowfs_entry *entry;
	struct inode *inode = NULL;

	if (dentry->d_name.len > 255)
		return ERR_PTR(-ENAMETOOLONG);

	entry = glowfs_find_child(dir->i_sb, parent, &dentry->d_name);
	if (entry) {
		inode = glowfs_make_inode(dir->i_sb, entry);
		if (!inode)
			return ERR_PTR(-ENOMEM);
	}

	d_add(dentry, inode);
	return NULL;
}

static int glowfs_iterate_shared(struct file *file, struct dir_context *ctx)
{
	struct inode *inode = file_inode(file);
	struct glowfs_entry *parent = inode->i_private;
	struct glowfs_sb_info *sbi = glowfs_sbi(inode->i_sb);
	loff_t emitted = 2;
	u32 i;

	if (!dir_emit_dots(file, ctx))
		return 0;

	for (i = 0; i < sbi->entry_count; i++) {
		struct glowfs_entry *entry = &sbi->entries[i];
		unsigned int type;

		if (entry->parent != parent->inode || entry->inode == parent->inode)
			continue;
		if (ctx->pos > emitted) {
			emitted++;
			continue;
		}
		if (entry->kind == GLOWFS_KIND_DIR)
			type = DT_DIR;
		else if (entry->kind == GLOWFS_KIND_SYMLINK)
			type = DT_LNK;
		else
			type = DT_REG;
		if (!dir_emit(ctx, entry->name, entry->name_len, entry->inode, type))
			return 0;
		ctx->pos = ++emitted;
	}
	return 0;
}

static int glowfs_fill_folio(struct inode *inode, struct folio *folio)
{
	struct glowfs_entry *entry = inode->i_private;
	loff_t pos = folio_pos(folio);
	size_t size = folio_size(folio);
	size_t copied = 0;
	void *addr;
	int ret = 0;

	addr = kmap_local_folio(folio, 0);
	if (pos < i_size_read(inode)) {
		copied = min_t(u64, size, i_size_read(inode) - pos);
		if (entry->data_offset > U64_MAX - pos)
			ret = -EIO;
		else
			ret = glowfs_read_bytes(inode->i_sb, entry->data_offset + pos, addr, copied);
	}
	if (!ret && copied < size)
		memset((u8 *)addr + copied, 0, size - copied);
	kunmap_local(addr);

	if (ret)
		return ret;
	flush_dcache_folio(folio);
	folio_mark_uptodate(folio);
	return 0;
}

static int glowfs_read_folio(struct file *file, struct folio *folio)
{
	int ret = glowfs_fill_folio(folio->mapping->host, folio);

	folio_unlock(folio);
	return ret;
}

static void glowfs_readahead(struct readahead_control *rac)
{
	struct folio *folio;

	while ((folio = readahead_folio(rac))) {
		if (!glowfs_fill_folio(rac->mapping->host, folio))
			folio_mark_uptodate(folio);
		folio_unlock(folio);
	}
}

static void glowfs_free_link(void *link)
{
	kfree(link);
}

static const char *glowfs_get_link(struct dentry *dentry, struct inode *inode, struct delayed_call *done)
{
	struct glowfs_entry *entry = inode->i_private;
	char *target;
	int ret;

	if (!dentry)
		return ERR_PTR(-ECHILD);
	if (entry->size > PATH_MAX)
		return ERR_PTR(-ENAMETOOLONG);
	target = kmalloc(entry->size + 1, GFP_KERNEL);
	if (!target)
		return ERR_PTR(-ENOMEM);
	ret = glowfs_read_bytes(inode->i_sb, entry->data_offset, target, entry->size);
	if (ret) {
		kfree(target);
		return ERR_PTR(ret);
	}
	target[entry->size] = '\0';
	set_delayed_call(done, glowfs_free_link, target);
	return target;
}

/* Modern kernel: use filemap helpers directly */
static int glowfs_write_begin(struct file *file, struct address_space *mapping,
				loff_t pos, unsigned int len, struct folio **foliop,
				void **fsdata)
{
	struct inode *inode = mapping->host;
	struct glowfs_entry *entry = inode->i_private;
	struct glowfs_sb_info *sbi = glowfs_sbi(inode->i_sb);
	pgoff_t index = pos >> PAGE_SHIFT;
	struct folio *folio;
	int ret;

	if (pos < 0)
		return -EINVAL;
	if (!(sbi->flags & GLOWFS_FLAG_MUTABLE))
		return -EROFS;
	if (len > U64_MAX - pos)
		return -EFBIG;
	if ((u64)pos + len > entry->size && pos != entry->size)
		return -EFBIG;

	folio = __filemap_get_folio(mapping, index, FGP_WRITEBEGIN,
				    mapping_gfp_mask(mapping));
	if (IS_ERR(folio))
		return PTR_ERR(folio);

	if (!folio_test_uptodate(folio)) {
		ret = glowfs_fill_folio(inode, folio);
		if (ret) {
			folio_unlock(folio);
			folio_put(folio);
			return ret;
		}
	}

	*foliop = folio;
	return 0;
}

static int glowfs_write_end(struct file *file, struct address_space *mapping,
			    loff_t pos, unsigned int len, unsigned int copied,
			    struct folio *folio, void *fsdata)
{
	struct inode *inode = mapping->host;
	struct glowfs_entry *entry = inode->i_private;
	struct glowfs_sb_info *sbi = glowfs_sbi(inode->i_sb);
	u64 end;
	u64 old_offset;
	u64 old_size;
	int ret;

	if (copied == 0)
		goto out;
	if (pos > entry->size || copied > U64_MAX - pos) {
		copied = 0;
		goto out;
	}
	end = pos + copied;
	if (end > entry->size) {
		mutex_lock(&sbi->allocation_lock);
		old_offset = entry->data_offset;
		old_size = entry->size;
		entry->data_offset = glowfs_align8(sbi->image_size);
		entry->size = end;
		sbi->image_size = glowfs_align8(entry->data_offset + entry->size);

		if (old_size > 0) {
			u8 *copy = kmalloc(PAGE_SIZE, GFP_KERNEL);
			u64 done = 0;

			if (!copy) {
				entry->data_offset = old_offset;
				entry->size = old_size;
				mutex_unlock(&sbi->allocation_lock);
				copied = 0;
				goto out;
			}
			while (done < old_size) {
				size_t chunk = min_t(u64, PAGE_SIZE, old_size - done);

				ret = glowfs_read_bytes(inode->i_sb, old_offset + done, copy, chunk);
				if (!ret)
					ret = glowfs_write_bytes(inode->i_sb, entry->data_offset + done, copy, chunk);
				if (ret) {
					kfree(copy);
					entry->data_offset = old_offset;
					entry->size = old_size;
					mutex_unlock(&sbi->allocation_lock);
					copied = 0;
					goto out;
				}
				done += chunk;
			}
			kfree(copy);
		}

		ret = glowfs_write_header_image_size(inode->i_sb, sbi->image_size);
		if (!ret)
			ret = glowfs_write_disk_entry(inode->i_sb, entry);
		mutex_unlock(&sbi->allocation_lock);
		if (ret) {
			entry->data_offset = old_offset;
			entry->size = old_size;
			i_size_write(inode, old_size);
			copied = 0;
			goto out;
		}
		i_size_write(inode, entry->size);
	}

	/* Write folio contents to disk */
	{
		loff_t wpos = folio_pos(folio);
		size_t wsize = folio_size(folio);
		size_t written;
		void *addr;

		if (wpos < entry->size) {
			written = min_t(u64, wsize, entry->size - wpos);
			addr = kmap_local_folio(folio, 0);
			ret = glowfs_write_bytes(inode->i_sb, entry->data_offset + wpos, addr, written);
			if (ret)
				copied = 0;
			kunmap_local(addr);
		}
	}

	if (!ret) {
		filemap_dirty_folio(mapping, folio);
		folio_mark_uptodate(folio);
		mark_inode_dirty(inode);
	}

out:
	folio_unlock(folio);
	folio_put(folio);
	return copied;
}

static int glowfs_writepage(struct page *page, struct writeback_control *wbc)
{
	struct folio *folio = page_folio(page);
	struct inode *inode = folio->mapping->host;
	struct glowfs_entry *entry = inode->i_private;
	loff_t pos = folio_pos(folio);
	size_t size = folio_size(folio);
	size_t written;
	void *addr;
	int ret;

	if (pos >= entry->size)
		return 0;
	written = min_t(u64, size, entry->size - pos);
	addr = kmap_local_folio(folio, 0);
	ret = glowfs_write_bytes(inode->i_sb, entry->data_offset + pos, addr, written);
	kunmap_local(addr);
	folio_unlock(folio);
	return ret;
}

static const struct inode_operations glowfs_dir_inode_ops = {
	.lookup = glowfs_lookup,
};

static const struct inode_operations glowfs_symlink_inode_ops = {
	.get_link = glowfs_get_link,
};

static const struct file_operations glowfs_dir_ops = {
	.owner = THIS_MODULE,
	.iterate_shared = glowfs_iterate_shared,
	.llseek = generic_file_llseek,
};

static const struct file_operations glowfs_file_ops = {
	.owner = THIS_MODULE,
	.read_iter = generic_file_read_iter,
	.write_iter = generic_file_write_iter,
	.mmap = generic_file_mmap,
	.splice_read = filemap_splice_read,
	.fsync = generic_file_fsync,
	.llseek = generic_file_llseek,
};

static const struct address_space_operations glowfs_aops = {
	.writepage = glowfs_writepage,
	.read_folio = glowfs_read_folio,
	.readahead = glowfs_readahead,
	.write_begin = glowfs_write_begin,
	.write_end = glowfs_write_end,
	.dirty_folio = filemap_dirty_folio,
};

static int glowfs_load_entries(struct super_block *sb, struct glowfs_disk_header *header)
{
	struct glowfs_sb_info *sbi = glowfs_sbi(sb);
	u64 entries_offset = le64_to_cpu(header->entries_offset);
	u64 names_offset = le64_to_cpu(header->names_offset);
	u64 data_offset = le64_to_cpu(header->data_offset);
	u64 image_size = le64_to_cpu(header->image_size);
	u64 flags = le64_to_cpu(header->flags);
	u32 entry_count = le32_to_cpu(header->entry_count);
	u64 names_size;
	u32 i;
	int ret;

	if (entry_count == 0 || entry_count > GLOWFS_MAX_ENTRIES)
		return -EINVAL;
	names_size = data_offset - names_offset;
	if (names_size > GLOWFS_MAX_NAMES_SIZE)
		return -EINVAL;

	sbi->entry_count = entry_count;
	sbi->names_size = names_size;
	sbi->flags = flags;
	sbi->image_size = image_size;
	mutex_init(&sbi->allocation_lock);
	sbi->entries = kcalloc(entry_count, sizeof(*sbi->entries), GFP_KERNEL);
	if (!sbi->entries)
		return -ENOMEM;

	sbi->names = kmalloc(names_size + 1, GFP_KERNEL);
	if (!sbi->names)
		return -ENOMEM;

	ret = glowfs_read_bytes(sb, names_offset, sbi->names, names_size);
	if (ret)
		return ret;
	sbi->names[names_size] = '\0';

	for (i = 0; i < entry_count; i++) {
		struct glowfs_disk_entry disk;
		struct glowfs_entry *entry = &sbi->entries[i];

		ret = glowfs_read_bytes(sb, entries_offset + i * sizeof(disk), &disk, sizeof(disk));
		if (ret)
			return ret;

		entry->index = i;
		entry->inode = le64_to_cpu(disk.inode);
		entry->parent = le64_to_cpu(disk.parent);
		entry->name_offset = le64_to_cpu(disk.name_offset);
		entry->name_len = le32_to_cpu(disk.name_len);
		entry->kind = le32_to_cpu(disk.kind);
		entry->mode = le32_to_cpu(disk.mode);
		entry->uid = le32_to_cpu(disk.uid);
		entry->gid = le32_to_cpu(disk.gid);
		entry->data_offset = le64_to_cpu(disk.data_offset);
		entry->size = le64_to_cpu(disk.size);
		memcpy(entry->digest, disk.digest, sizeof(entry->digest));

		if (entry->name_offset > names_size || entry->name_len > names_size - entry->name_offset)
			return -EINVAL;
		if (entry->kind != GLOWFS_KIND_DIR && entry->kind != GLOWFS_KIND_FILE && entry->kind != GLOWFS_KIND_SYMLINK)
			return -EINVAL;
		if (!(flags & GLOWFS_FLAG_MUTABLE) && entry->kind == GLOWFS_KIND_FILE && entry->mode & 0222)
			return -EINVAL;
		if (entry->kind == GLOWFS_KIND_DIR && (entry->size || entry->data_offset))
			return -EINVAL;
		if (entry->kind != GLOWFS_KIND_DIR && (entry->data_offset > image_size || entry->size > image_size - entry->data_offset))
			return -EINVAL;
		if (entry->name_len && memchr(sbi->names + entry->name_offset, '/', entry->name_len))
			return -EINVAL;
		entry->name = sbi->names + entry->name_offset;
	}

	if (sbi->entries[0].inode != 1 || sbi->entries[0].parent != 1 || sbi->entries[0].kind != GLOWFS_KIND_DIR)
		return -EINVAL;
	if (sbi->entries[0].name_len != 0)
		return -EINVAL;

	for (i = 0; i < entry_count; i++) {
		u32 j;
		bool parent_found = sbi->entries[i].inode == 1 && sbi->entries[i].parent == 1;

		for (j = 0; j < entry_count; j++) {
			if (i != j && sbi->entries[i].inode == sbi->entries[j].inode)
				return -EINVAL;
			if (sbi->entries[j].inode == sbi->entries[i].parent)
				parent_found = true;
		}
		if (!parent_found)
			return -EINVAL;
	}

	return 0;
}

static int glowfs_load_v2_superblock(struct super_block *sb)
{
	struct glowfs_sb_info *sbi = glowfs_sbi(sb);
	struct glowfs_v2_superblock v2;
	u64 offset = glowfs_align8(sbi->image_size);
	u64 block_size;
	u64 bitmap_offset;
	u64 bitmap_len;
	u64 extent_table_offset;
	u64 extent_table_len;
	u64 journal_offset;
	u64 journal_len;
	u64 data_start;
	u64 total_blocks;
	u64 free_blocks;
	int ret;

	if (!(sbi->flags & GLOWFS_FLAG_V2))
		return 0;
	ret = glowfs_read_bytes(sb, offset, &v2, sizeof(v2));
	if (ret)
		return ret;
	if (memcmp(v2.magic, GLOWFS_V2_MAGIC_STRING, sizeof(v2.magic)))
		return -EINVAL;
	if (le32_to_cpu(v2.version) != GLOWFS_V2_VERSION)
		return -EINVAL;
	block_size = le64_to_cpu(v2.block_size);
	bitmap_offset = le64_to_cpu(v2.bitmap_offset);
	bitmap_len = le64_to_cpu(v2.bitmap_len);
	extent_table_offset = le64_to_cpu(v2.extent_table_offset);
	extent_table_len = le64_to_cpu(v2.extent_table_len);
	journal_offset = le64_to_cpu(v2.journal_offset);
	journal_len = le64_to_cpu(v2.journal_len);
	data_start = le64_to_cpu(v2.data_start);
	total_blocks = le64_to_cpu(v2.total_blocks);
	free_blocks = le64_to_cpu(v2.free_blocks);

	if (block_size != GLOWFS_V2_BLOCK_SIZE)
		return -EINVAL;
	if (bitmap_offset < offset + GLOWFS_V2_SUPERBLOCK_LEN)
		return -EINVAL;
	if (extent_table_offset < bitmap_offset + bitmap_len)
		return -EINVAL;
	if (journal_offset < extent_table_offset + extent_table_len)
		return -EINVAL;
	if (data_start < journal_offset + journal_len)
		return -EINVAL;
	if (!total_blocks || free_blocks > total_blocks)
		return -EINVAL;
	sbi->v2_total_blocks = total_blocks;
	sbi->v2_free_blocks = free_blocks;
	return 0;
}

static void glowfs_put_super(struct super_block *sb)
{
	struct glowfs_sb_info *sbi = glowfs_sbi(sb);

	if (!sbi)
		return;
	kfree(sbi->entries);
	kfree(sbi->names);
	kfree(sbi);
	sb->s_fs_info = NULL;
}

static int glowfs_statfs(struct dentry *dentry, struct kstatfs *buf)
{
	struct super_block *sb = dentry->d_sb;
	struct glowfs_sb_info *sbi = glowfs_sbi(sb);

	buf->f_type = GLOWFS_SUPER_MAGIC;
	buf->f_bsize = sb->s_blocksize;
	buf->f_blocks = sbi && sbi->v2_total_blocks ? sbi->v2_total_blocks : 1;
	buf->f_bfree = sbi && sbi->v2_total_blocks ? sbi->v2_free_blocks : 0;
	buf->f_bavail = buf->f_bfree;
	buf->f_files = sbi ? sbi->entry_count : 0;
	buf->f_ffree = 0;
	buf->f_namelen = 255;
	return 0;
}

static int glowfs_sync_fs(struct super_block *sb, int wait)
{
	return sync_blockdev(sb->s_bdev);
}

static const struct super_operations glowfs_super_ops = {
	.statfs = glowfs_statfs,
	.put_super = glowfs_put_super,
	.sync_fs = glowfs_sync_fs,
	.drop_inode = generic_delete_inode,
};

static int glowfs_fill_super(struct super_block *sb, void *data, int silent)
{
	struct inode *root_inode;
	struct glowfs_disk_header header;
	struct glowfs_sb_info *sbi;
	u64 image_flags;
	int ret;

	sb_set_blocksize(sb, 4096);
	ret = glowfs_read_bytes(sb, 0, &header, sizeof(header));
	if (ret)
		return ret;

	ret = glowfs_rust_validate_header(header);
	if (ret)
		return ret;

	sbi = kzalloc(sizeof(*sbi), GFP_KERNEL);
	if (!sbi)
		return -ENOMEM;

	sb->s_fs_info = sbi;
	sb->s_magic = GLOWFS_SUPER_MAGIC;
	sb->s_op = &glowfs_super_ops;
	sb->s_maxbytes = MAX_LFS_FILESIZE;
	image_flags = le64_to_cpu(header.flags);
	if (!(image_flags & GLOWFS_FLAG_MUTABLE))
		sb->s_flags |= SB_RDONLY;

	ret = glowfs_load_entries(sb, &header);
	if (ret)
		goto err;
	ret = glowfs_load_v2_superblock(sb);
	if (ret)
		goto err;
	if (sbi->flags & GLOWFS_FLAG_V2)
		sb->s_flags |= SB_RDONLY;

	root_inode = glowfs_make_inode(sb, glowfs_find_inode(sb, 1));
	if (!root_inode) {
		ret = -ENOMEM;
		goto err;
	}

	sb->s_root = d_make_root(root_inode);
	if (!sb->s_root) {
		ret = -ENOMEM;
		goto err;
	}

	return 0;

err:
	glowfs_put_super(sb);
	return ret;
}

/* Modern mount API using get_tree_bdev */
static int glowfs_get_tree(struct fs_context *fc)
{
	return get_tree_bdev(fc, glowfs_fill_super);
}

static const struct fs_context_operations glowfs_context_ops = {
	.get_tree = glowfs_get_tree,
};

static int glowfs_init_fs_context(struct fs_context *fc)
{
	fc->ops = &glowfs_context_ops;
	return 0;
}

static struct file_system_type glowfs_fs_type = {
	.owner = THIS_MODULE,
	.name = "glowfs",
	.init_fs_context = glowfs_init_fs_context,
	.kill_sb = kill_block_super,
	.fs_flags = FS_REQUIRES_DEV,
};

static int __init glowfs_init(void)
{
	return register_filesystem(&glowfs_fs_type);
}

static void __exit glowfs_exit(void)
{
	unregister_filesystem(&glowfs_fs_type);
}

module_init(glowfs_init);
module_exit(glowfs_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Alpenglow GlowFS — immutable root filesystem VFS shim");

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

#include "solfs_format.h"

#define SOLFS_MAX_ENTRIES 65536
#define SOLFS_MAX_NAMES_SIZE (16 * 1024 * 1024)
#define SOLFS_HAS_FOLIO_WRITE_CALLBACKS (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0))

int solfs_rust_validate_header(struct solfs_disk_header header);

__weak int solfs_rust_validate_header(struct solfs_disk_header header)
{
	u32 version = le32_to_cpu(header.version);
	u32 entry_count = le32_to_cpu(header.entry_count);
	u64 entries_offset = le64_to_cpu(header.entries_offset);
	u64 names_offset = le64_to_cpu(header.names_offset);
	u64 data_offset = le64_to_cpu(header.data_offset);
	u64 image_size = le64_to_cpu(header.image_size);
	u64 entries_len;

	if (memcmp(header.magic, SOLFS_MAGIC_STRING, sizeof(header.magic)))
		return -EINVAL;
	if (version != SOLFS_VERSION)
		return -EINVAL;
	if (!entry_count)
		return -EINVAL;
	if (check_mul_overflow((u64)entry_count, (u64)SOLFS_ENTRY_LEN, &entries_len))
		return -EINVAL;
	if (entries_offset != SOLFS_HEADER_LEN)
		return -EINVAL;
	if (names_offset < entries_offset + entries_len)
		return -EINVAL;
	if (data_offset < names_offset)
		return -EINVAL;
	if (image_size < data_offset)
		return -EINVAL;
	return 0;
}

struct solfs_entry {
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

struct solfs_sb_info {
	u32 entry_count;
	u64 names_size;
	u64 flags;
	u64 image_size;
	u64 v2_total_blocks;
	u64 v2_free_blocks;
	struct mutex allocation_lock;
	struct solfs_entry *entries;
	char *names;
};

static const struct inode_operations solfs_dir_inode_ops;
static const struct inode_operations solfs_symlink_inode_ops;
static const struct file_operations solfs_dir_ops;
static const struct file_operations solfs_file_ops;
static const struct address_space_operations solfs_aops;
static int solfs_write_folio(struct inode *inode, struct folio *folio);

static struct solfs_sb_info *solfs_sbi(struct super_block *sb)
{
	return sb->s_fs_info;
}

static int solfs_read_bytes(struct super_block *sb, u64 offset, void *dst, size_t len)
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

static int solfs_write_bytes(struct super_block *sb, u64 offset, const void *src, size_t len)
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
		sync_dirty_buffer(bh);
		brelse(bh);
		in += chunk;
		offset += chunk;
		len -= chunk;
	}
	return 0;
}

static u64 solfs_align8(u64 value)
{
	return (value + 7) & ~7ULL;
}

static int solfs_write_header_image_size(struct super_block *sb, u64 image_size)
{
	struct solfs_disk_header header;
	int ret;

	ret = solfs_read_bytes(sb, 0, &header, sizeof(header));
	if (ret)
		return ret;
	header.image_size = cpu_to_le64(image_size);
	return solfs_write_bytes(sb, 0, &header, sizeof(header));
}

static int solfs_write_disk_entry(struct super_block *sb, struct solfs_entry *entry)
{
	struct solfs_disk_entry disk;
	u64 offset = SOLFS_HEADER_LEN + entry->index * SOLFS_ENTRY_LEN;

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
	return solfs_write_bytes(sb, offset, &disk, sizeof(disk));
}

static struct solfs_entry *solfs_find_inode(struct super_block *sb, u64 inode)
{
	struct solfs_sb_info *sbi = solfs_sbi(sb);
	u32 i;

	for (i = 0; i < sbi->entry_count; i++) {
		if (sbi->entries[i].inode == inode)
			return &sbi->entries[i];
	}
	return NULL;
}

static struct solfs_entry *solfs_find_child(struct super_block *sb, struct solfs_entry *parent, const struct qstr *name)
{
	struct solfs_sb_info *sbi = solfs_sbi(sb);
	u32 i;

	for (i = 0; i < sbi->entry_count; i++) {
		struct solfs_entry *entry = &sbi->entries[i];

		if (entry->parent != parent->inode || entry->inode == parent->inode)
			continue;
		if (entry->name_len != name->len)
			continue;
		if (!memcmp(entry->name, name->name, name->len))
			return entry;
	}
	return NULL;
}

static struct inode *solfs_make_inode(struct super_block *sb, struct solfs_entry *entry)
{
	struct inode *inode = iget_locked(sb, entry->inode);
	umode_t mode;

	if (!inode)
		return NULL;
	if (!(inode->i_state & I_NEW))
		return inode;

	mode = entry->mode & 0777;
	if (entry->kind == SOLFS_KIND_DIR)
		mode |= S_IFDIR;
	else if (entry->kind == SOLFS_KIND_SYMLINK)
		mode |= S_IFLNK;
	else
		mode |= S_IFREG;

	inode->i_ino = entry->inode;
	inode->i_mode = mode;
	inode->i_uid = make_kuid(&init_user_ns, entry->uid);
	inode->i_gid = make_kgid(&init_user_ns, entry->gid);
	inode->i_size = entry->size;
	inode->i_private = entry;
	inode->i_mapping->a_ops = &solfs_aops;
	inode_set_atime_to_ts(inode, current_time(inode));
	inode_set_mtime_to_ts(inode, current_time(inode));
	inode_set_ctime_current(inode);

	if (entry->kind == SOLFS_KIND_DIR) {
		inode->i_op = &solfs_dir_inode_ops;
		inode->i_fop = &solfs_dir_ops;
		set_nlink(inode, 2);
	} else if (entry->kind == SOLFS_KIND_SYMLINK) {
		inode->i_op = &solfs_symlink_inode_ops;
		inode_nohighmem(inode);
		set_nlink(inode, 1);
	} else {
		inode->i_fop = &solfs_file_ops;
		set_nlink(inode, 1);
	}

	unlock_new_inode(inode);
	return inode;
}

static struct dentry *solfs_lookup(struct inode *dir, struct dentry *dentry, unsigned int flags)
{
	struct solfs_entry *parent = dir->i_private;
	struct solfs_entry *entry;
	struct inode *inode = NULL;

	if (dentry->d_name.len > 255)
		return ERR_PTR(-ENAMETOOLONG);

	entry = solfs_find_child(dir->i_sb, parent, &dentry->d_name);
	if (entry) {
		inode = solfs_make_inode(dir->i_sb, entry);
		if (!inode)
			return ERR_PTR(-ENOMEM);
	}

	d_add(dentry, inode);
	return NULL;
}

static int solfs_iterate_shared(struct file *file, struct dir_context *ctx)
{
	struct inode *inode = file_inode(file);
	struct solfs_entry *parent = inode->i_private;
	struct solfs_sb_info *sbi = solfs_sbi(inode->i_sb);
	loff_t emitted = 2;
	u32 i;

	if (!dir_emit_dots(file, ctx))
		return 0;

	for (i = 0; i < sbi->entry_count; i++) {
		struct solfs_entry *entry = &sbi->entries[i];
		unsigned int type;

		if (entry->parent != parent->inode || entry->inode == parent->inode)
			continue;
		if (ctx->pos > emitted) {
			emitted++;
			continue;
		}
		if (entry->kind == SOLFS_KIND_DIR)
			type = DT_DIR;
		else if (entry->kind == SOLFS_KIND_SYMLINK)
			type = DT_LNK;
		else
			type = DT_REG;
		if (!dir_emit(ctx, entry->name, entry->name_len, entry->inode, type))
			return 0;
		ctx->pos = ++emitted;
	}
	return 0;
}

static int solfs_fill_folio(struct inode *inode, struct folio *folio)
{
	struct solfs_entry *entry = inode->i_private;
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
			ret = solfs_read_bytes(inode->i_sb, entry->data_offset + pos, addr, copied);
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

static int solfs_read_folio(struct file *file, struct folio *folio)
{
	int ret = solfs_fill_folio(folio->mapping->host, folio);

	folio_unlock(folio);
	return ret;
}

static void solfs_readahead(struct readahead_control *rac)
{
	struct folio *folio;

	while ((folio = readahead_folio(rac))) {
		if (!solfs_fill_folio(rac->mapping->host, folio))
			folio_mark_uptodate(folio);
		folio_unlock(folio);
	}
}

static void solfs_free_link(void *link)
{
	kfree(link);
}

static const char *solfs_get_link(struct dentry *dentry, struct inode *inode, struct delayed_call *done)
{
	struct solfs_entry *entry = inode->i_private;
	char *target;
	int ret;

	if (!dentry)
		return ERR_PTR(-ECHILD);
	if (entry->size > PATH_MAX)
		return ERR_PTR(-ENAMETOOLONG);
	target = kmalloc(entry->size + 1, GFP_KERNEL);
	if (!target)
		return ERR_PTR(-ENOMEM);
	ret = solfs_read_bytes(inode->i_sb, entry->data_offset, target, entry->size);
	if (ret) {
		kfree(target);
		return ERR_PTR(ret);
	}
	target[entry->size] = '\0';
	set_delayed_call(done, solfs_free_link, target);
	return target;
}

static int solfs_write_begin_common(struct address_space *mapping, loff_t pos, unsigned int len, struct folio **foliop)
{
	struct inode *inode = mapping->host;
	struct solfs_entry *entry = inode->i_private;
	struct solfs_sb_info *sbi = solfs_sbi(inode->i_sb);
	struct page *page;
	pgoff_t index = pos >> PAGE_SHIFT;
	int ret;

	if (pos < 0)
		return -EINVAL;
	if (!(sbi->flags & SOLFS_FLAG_MUTABLE))
		return -EROFS;
	if (len > U64_MAX - pos)
		return -EFBIG;
	if ((u64)pos + len > entry->size && pos != entry->size)
		return -EFBIG;

	page = grab_cache_page_write_begin(mapping, index);
	if (!page)
		return -ENOMEM;

	if (!PageUptodate(page)) {
		ret = solfs_fill_folio(inode, page_folio(page));
		if (ret) {
			unlock_page(page);
			put_page(page);
			return ret;
		}
	}

	*foliop = page_folio(page);
	return 0;
}

static int solfs_write_end_common(struct address_space *mapping, loff_t pos, unsigned int copied, struct folio *folio)
{
	struct inode *inode = mapping->host;
	struct solfs_entry *entry = inode->i_private;
	struct solfs_sb_info *sbi = solfs_sbi(inode->i_sb);
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
		entry->data_offset = solfs_align8(sbi->image_size);
		entry->size = end;
		sbi->image_size = solfs_align8(entry->data_offset + entry->size);

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

				ret = solfs_read_bytes(inode->i_sb, old_offset + done, copy, chunk);
				if (!ret)
					ret = solfs_write_bytes(inode->i_sb, entry->data_offset + done, copy, chunk);
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

		ret = solfs_write_header_image_size(inode->i_sb, sbi->image_size);
		if (!ret)
			ret = solfs_write_disk_entry(inode->i_sb, entry);
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

	ret = solfs_write_folio(inode, folio);
	if (ret) {
		copied = 0;
		goto out;
	}
	folio_mark_dirty(folio);
	folio_mark_uptodate(folio);
	mark_inode_dirty(inode);

out:
	folio_unlock(folio);
	folio_put(folio);
	return copied;
}

#if SOLFS_HAS_FOLIO_WRITE_CALLBACKS
static int solfs_write_begin(struct file *file, struct address_space *mapping, loff_t pos, unsigned int len, struct folio **foliop, void **fsdata)
{
	return solfs_write_begin_common(mapping, pos, len, foliop);
}

static int solfs_write_end(struct file *file, struct address_space *mapping, loff_t pos, unsigned int len, unsigned int copied, struct folio *folio, void *fsdata)
{
	return solfs_write_end_common(mapping, pos, copied, folio);
}
#else
static int solfs_write_begin(struct file *file, struct address_space *mapping, loff_t pos, unsigned int len, struct page **pagep, void **fsdata)
{
	struct folio *folio;
	int ret;

	ret = solfs_write_begin_common(mapping, pos, len, &folio);
	if (ret)
		return ret;
	*pagep = folio_page(folio, 0);
	return 0;
}

static int solfs_write_end(struct file *file, struct address_space *mapping, loff_t pos, unsigned int len, unsigned int copied, struct page *page, void *fsdata)
{
	return solfs_write_end_common(mapping, pos, copied, page_folio(page));
}
#endif

static int solfs_write_folio(struct inode *inode, struct folio *folio)
{
	struct solfs_entry *entry = inode->i_private;
	loff_t pos = folio_pos(folio);
	size_t size = folio_size(folio);
	size_t written;
	void *addr;
	int ret;

	if (pos >= entry->size)
		return 0;
	written = min_t(u64, size, entry->size - pos);
	addr = kmap_local_folio(folio, 0);
	ret = solfs_write_bytes(inode->i_sb, entry->data_offset + pos, addr, written);
	kunmap_local(addr);
	return ret;
}

static int solfs_writepage(struct page *page, struct writeback_control *wbc)
{
	struct folio *folio = page_folio(page);
	struct inode *inode = folio->mapping->host;
	int ret;

	folio_start_writeback(folio);
	ret = solfs_write_folio(inode, folio);
	folio_end_writeback(folio);
	folio_unlock(folio);
	return ret;
}

static const struct inode_operations solfs_dir_inode_ops = {
	.lookup = solfs_lookup,
};

static const struct inode_operations solfs_symlink_inode_ops = {
	.get_link = solfs_get_link,
};

static const struct file_operations solfs_dir_ops = {
	.owner = THIS_MODULE,
	.iterate_shared = solfs_iterate_shared,
	.llseek = generic_file_llseek,
};

static const struct file_operations solfs_file_ops = {
	.owner = THIS_MODULE,
	.read_iter = generic_file_read_iter,
	.write_iter = generic_file_write_iter,
	.mmap = generic_file_mmap,
	.splice_read = filemap_splice_read,
	.fsync = generic_file_fsync,
	.llseek = generic_file_llseek,
};

static const struct address_space_operations solfs_aops = {
	.writepage = solfs_writepage,
	.read_folio = solfs_read_folio,
	.readahead = solfs_readahead,
	.write_begin = solfs_write_begin,
	.write_end = solfs_write_end,
	.dirty_folio = filemap_dirty_folio,
};

static int solfs_load_entries(struct super_block *sb, struct solfs_disk_header *header)
{
	struct solfs_sb_info *sbi = solfs_sbi(sb);
	u64 entries_offset = le64_to_cpu(header->entries_offset);
	u64 names_offset = le64_to_cpu(header->names_offset);
	u64 data_offset = le64_to_cpu(header->data_offset);
	u64 image_size = le64_to_cpu(header->image_size);
	u64 flags = le64_to_cpu(header->flags);
	u32 entry_count = le32_to_cpu(header->entry_count);
	u64 names_size;
	u32 i;
	int ret;

	if (entry_count == 0 || entry_count > SOLFS_MAX_ENTRIES)
		return -EINVAL;
	names_size = data_offset - names_offset;
	if (names_size > SOLFS_MAX_NAMES_SIZE)
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

	ret = solfs_read_bytes(sb, names_offset, sbi->names, names_size);
	if (ret)
		return ret;
	sbi->names[names_size] = '\0';

	for (i = 0; i < entry_count; i++) {
		struct solfs_disk_entry disk;
		struct solfs_entry *entry = &sbi->entries[i];

		ret = solfs_read_bytes(sb, entries_offset + i * sizeof(disk), &disk, sizeof(disk));
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
		if (entry->kind != SOLFS_KIND_DIR && entry->kind != SOLFS_KIND_FILE && entry->kind != SOLFS_KIND_SYMLINK)
			return -EINVAL;
		if (!(flags & SOLFS_FLAG_MUTABLE) && entry->kind == SOLFS_KIND_FILE && entry->mode & 0222)
			return -EINVAL;
		if (entry->kind == SOLFS_KIND_DIR && (entry->size || entry->data_offset))
			return -EINVAL;
		if (entry->kind != SOLFS_KIND_DIR && (entry->data_offset > image_size || entry->size > image_size - entry->data_offset))
			return -EINVAL;
		if (entry->name_len && memchr(sbi->names + entry->name_offset, '/', entry->name_len))
			return -EINVAL;
		entry->name = sbi->names + entry->name_offset;
	}

	if (sbi->entries[0].inode != 1 || sbi->entries[0].parent != 1 || sbi->entries[0].kind != SOLFS_KIND_DIR)
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

static int solfs_load_v2_superblock(struct super_block *sb)
{
	struct solfs_sb_info *sbi = solfs_sbi(sb);
	struct solfs_v2_superblock v2;
	u64 offset = solfs_align8(sbi->image_size);
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

	if (!(sbi->flags & SOLFS_FLAG_V2))
		return 0;
	ret = solfs_read_bytes(sb, offset, &v2, sizeof(v2));
	if (ret)
		return ret;
	if (memcmp(v2.magic, SOLFS_V2_MAGIC_STRING, sizeof(v2.magic)))
		return -EINVAL;
	if (le32_to_cpu(v2.version) != SOLFS_V2_VERSION)
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

	if (block_size != SOLFS_V2_BLOCK_SIZE)
		return -EINVAL;
	if (bitmap_offset < offset + SOLFS_V2_SUPERBLOCK_LEN)
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

static void solfs_put_super(struct super_block *sb)
{
	struct solfs_sb_info *sbi = solfs_sbi(sb);

	if (!sbi)
		return;
	kfree(sbi->entries);
	kfree(sbi->names);
	kfree(sbi);
	sb->s_fs_info = NULL;
}

static int solfs_statfs(struct dentry *dentry, struct kstatfs *buf)
{
	struct super_block *sb = dentry->d_sb;
	struct solfs_sb_info *sbi = solfs_sbi(sb);

	buf->f_type = SOLFS_SUPER_MAGIC;
	buf->f_bsize = sb->s_blocksize;
	buf->f_blocks = sbi && sbi->v2_total_blocks ? sbi->v2_total_blocks : 1;
	buf->f_bfree = sbi && sbi->v2_total_blocks ? sbi->v2_free_blocks : 0;
	buf->f_bavail = buf->f_bfree;
	buf->f_files = sbi ? sbi->entry_count : 0;
	buf->f_ffree = 0;
	buf->f_namelen = 255;
	return 0;
}

static const struct super_operations solfs_super_ops = {
	.statfs = solfs_statfs,
	.put_super = solfs_put_super,
	.drop_inode = generic_delete_inode,
};

static int solfs_fill_super(struct super_block *sb, void *data, int silent)
{
	struct buffer_head *bh;
	struct inode *root_inode;
	struct solfs_disk_header header;
	struct solfs_sb_info *sbi;
	u64 image_flags;
	int ret;

	sb_set_blocksize(sb, 4096);
	bh = sb_bread(sb, 0);
	if (!bh)
		return -EINVAL;

	memcpy(&header, bh->b_data, sizeof(header));
	brelse(bh);

	ret = solfs_rust_validate_header(header);
	if (ret)
		return ret;

	sbi = kzalloc(sizeof(*sbi), GFP_KERNEL);
	if (!sbi)
		return -ENOMEM;

	sb->s_fs_info = sbi;
	sb->s_magic = SOLFS_SUPER_MAGIC;
	sb->s_op = &solfs_super_ops;
	sb->s_maxbytes = MAX_LFS_FILESIZE;
	image_flags = le64_to_cpu(header.flags);
	if (!(image_flags & SOLFS_FLAG_MUTABLE))
		sb->s_flags |= SB_RDONLY;

	ret = solfs_load_entries(sb, &header);
	if (ret)
		goto err;
	ret = solfs_load_v2_superblock(sb);
	if (ret)
		goto err;
	if (sbi->flags & SOLFS_FLAG_V2)
		sb->s_flags |= SB_RDONLY;

	root_inode = solfs_make_inode(sb, solfs_find_inode(sb, 1));
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
	solfs_put_super(sb);
	return ret;
}

static struct dentry *solfs_mount(struct file_system_type *fs_type, int flags, const char *dev_name, void *data)
{
	return mount_bdev(fs_type, flags, dev_name, data, solfs_fill_super);
}

static struct file_system_type solfs_fs_type = {
	.owner = THIS_MODULE,
	.name = "solfs",
	.mount = solfs_mount,
	.kill_sb = kill_block_super,
	.fs_flags = FS_REQUIRES_DEV,
};

static int __init solfs_init(void)
{
	return register_filesystem(&solfs_fs_type);
}

static void __exit solfs_exit(void)
{
	unregister_filesystem(&solfs_fs_type);
}

module_init(solfs_init);
module_exit(solfs_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Soliloquy filesystem VFS shim");

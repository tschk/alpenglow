use crate::{Entry, Header, KIND_FILE};
use std::fs::{self, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

pub const V2_MAGIC: &[u8; 8] = b"GLWFSV02";
pub const V2_BLOCK_SIZE: u64 = 4096;
pub const V2_SUPERBLOCK_LEN: u64 = 96;
pub const V2_EXTENT_RECORD_LEN: u64 = 40;
pub const V2_JOURNAL_RECORD_LEN: u64 = 64;
pub const V2_DEFAULT_JOURNAL_RECORDS: u64 = 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct V2Layout {
    pub block_size: u64,
    pub superblock_offset: u64,
    pub bitmap_offset: u64,
    pub bitmap_len: u64,
    pub extent_table_offset: u64,
    pub extent_table_len: u64,
    pub journal_offset: u64,
    pub journal_len: u64,
    pub data_start: u64,
    pub total_blocks: u64,
    pub free_blocks: u64,
    pub extents: Vec<V2Extent>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct V2Extent {
    pub inode: u64,
    pub logical_block: u64,
    pub physical_block: u64,
    pub block_count: u64,
    pub flags: u64,
}

pub fn plan_v2_layout(
    header: &Header,
    entries: &[Entry],
    target_size: u64,
) -> crate::Result<V2Layout> {
    if target_size < header.image_size {
        return Err(crate::GlowfsError::Invalid(
            "v2 target size is smaller than source image".to_string(),
        ));
    }
    let total_blocks = div_ceil(target_size, V2_BLOCK_SIZE);
    let bitmap_len = div_ceil(total_blocks, 8);
    let mut extents = file_extents(entries);
    let extent_table_len = extents.len() as u64 * V2_EXTENT_RECORD_LEN;
    let superblock_offset = align_block(header.image_size);
    let bitmap_offset = align_block(superblock_offset + V2_SUPERBLOCK_LEN);
    let extent_table_offset = align_block(bitmap_offset + bitmap_len);
    let journal_offset = align_block(extent_table_offset + extent_table_len);
    let journal_len = V2_DEFAULT_JOURNAL_RECORDS * V2_JOURNAL_RECORD_LEN;
    let data_start = align_block(journal_offset + journal_len);
    assign_physical_blocks(&mut extents, data_start / V2_BLOCK_SIZE);
    let metadata_blocks = div_ceil(data_start, V2_BLOCK_SIZE);
    let used_file_blocks = extents.iter().map(|extent| extent.block_count).sum::<u64>();
    let used_blocks = metadata_blocks.saturating_add(used_file_blocks);
    if used_blocks > total_blocks {
        return Err(crate::GlowfsError::Invalid(
            "v2 target size cannot fit metadata and file extents".to_string(),
        ));
    }
    let free_blocks = total_blocks.saturating_sub(used_blocks);

    Ok(V2Layout {
        block_size: V2_BLOCK_SIZE,
        superblock_offset,
        bitmap_offset,
        bitmap_len,
        extent_table_offset,
        extent_table_len,
        journal_offset,
        journal_len,
        data_start,
        total_blocks,
        free_blocks,
        extents,
    })
}

pub fn upgrade_image_to_v2(path: impl AsRef<Path>, target_size: u64) -> crate::Result<V2Layout> {
    let path = path.as_ref();
    let image = crate::inspect_image(path)?;
    if image.header.flags & crate::FLAG_MUTABLE == 0 {
        return Err(crate::GlowfsError::Invalid(
            "only mutable GlowFS images can be upgraded to v2".to_string(),
        ));
    }
    let layout = plan_v2_layout(&image.header, &image.entries, target_size)?;
    let mut file = OpenOptions::new().read(true).write(true).open(path)?;
    file.set_len(target_size)?;

    let mut entry_map = std::collections::HashMap::with_capacity(image.entries.len());
    for entry in &image.entries {
        entry_map.insert(entry.inode, entry);
    }

    for extent in &layout.extents {
        let entry = entry_map.get(&extent.inode).ok_or_else(|| {
            crate::GlowfsError::Invalid("v2 extent references missing inode".into())
        })?;
        file.seek(SeekFrom::Start(entry.data_offset))?;
        let mut data = vec![0_u8; entry.size as usize];
        file.read_exact(&mut data)?;
        file.seek(SeekFrom::Start(extent.physical_block * V2_BLOCK_SIZE))?;
        file.write_all(&data)?;
    }

    write_superblock(&mut file, &layout)?;
    write_bitmap(&mut file, &layout)?;
    write_extents(&mut file, &layout)?;
    zero_region(&mut file, layout.journal_offset, layout.journal_len)?;
    mark_image_v2(&mut file, &image.header)?;
    file.flush()?;
    Ok(layout)
}

fn file_extents(entries: &[Entry]) -> Vec<V2Extent> {
    let mut extents = Vec::new();
    for entry in entries {
        if entry.kind != KIND_FILE || entry.size == 0 {
            continue;
        }
        extents.push(V2Extent {
            inode: entry.inode,
            logical_block: 0,
            physical_block: 0,
            block_count: div_ceil(entry.size, V2_BLOCK_SIZE),
            flags: 0,
        });
    }
    extents
}

fn write_superblock(file: &mut fs::File, layout: &V2Layout) -> crate::Result<()> {
    file.seek(SeekFrom::Start(layout.superblock_offset))?;
    file.write_all(V2_MAGIC)?;
    file.write_all(&2_u32.to_le_bytes())?;
    file.write_all(&0_u32.to_le_bytes())?;
    file.write_all(&layout.block_size.to_le_bytes())?;
    file.write_all(&layout.bitmap_offset.to_le_bytes())?;
    file.write_all(&layout.bitmap_len.to_le_bytes())?;
    file.write_all(&layout.extent_table_offset.to_le_bytes())?;
    file.write_all(&layout.extent_table_len.to_le_bytes())?;
    file.write_all(&layout.journal_offset.to_le_bytes())?;
    file.write_all(&layout.journal_len.to_le_bytes())?;
    file.write_all(&layout.data_start.to_le_bytes())?;
    file.write_all(&layout.total_blocks.to_le_bytes())?;
    file.write_all(&layout.free_blocks.to_le_bytes())?;
    Ok(())
}

fn write_bitmap(file: &mut fs::File, layout: &V2Layout) -> crate::Result<()> {
    let mut bitmap = vec![0_u8; layout.bitmap_len as usize];
    let metadata_blocks = div_ceil(layout.data_start, V2_BLOCK_SIZE);
    for block in 0..metadata_blocks {
        mark_block(&mut bitmap, block);
    }
    for extent in &layout.extents {
        for block in extent.physical_block..extent.physical_block + extent.block_count {
            mark_block(&mut bitmap, block);
        }
    }
    file.seek(SeekFrom::Start(layout.bitmap_offset))?;
    file.write_all(&bitmap)?;
    Ok(())
}

fn write_extents(file: &mut fs::File, layout: &V2Layout) -> crate::Result<()> {
    file.seek(SeekFrom::Start(layout.extent_table_offset))?;
    for extent in &layout.extents {
        file.write_all(&extent.inode.to_le_bytes())?;
        file.write_all(&extent.logical_block.to_le_bytes())?;
        file.write_all(&extent.physical_block.to_le_bytes())?;
        file.write_all(&extent.block_count.to_le_bytes())?;
        file.write_all(&extent.flags.to_le_bytes())?;
    }
    Ok(())
}

fn zero_region(file: &mut fs::File, offset: u64, len: u64) -> crate::Result<()> {
    file.seek(SeekFrom::Start(offset))?;
    let zeroes = [0_u8; 4096];
    let mut remaining = len;
    while remaining > 0 {
        let chunk = remaining.min(zeroes.len() as u64) as usize;
        file.write_all(&zeroes[..chunk])?;
        remaining -= chunk as u64;
    }
    Ok(())
}

fn mark_image_v2(file: &mut fs::File, header: &Header) -> crate::Result<()> {
    file.seek(SeekFrom::Start(48))?;
    file.write_all(&(header.flags | crate::FLAG_V2).to_le_bytes())?;
    Ok(())
}

fn mark_block(bitmap: &mut [u8], block: u64) {
    let byte = block / 8;
    let bit = block % 8;
    if let Some(value) = bitmap.get_mut(byte as usize) {
        *value |= 1 << bit;
    }
}

fn assign_physical_blocks(extents: &mut [V2Extent], first_block: u64) {
    let mut cursor = first_block;
    for extent in extents {
        extent.physical_block = cursor;
        cursor += extent.block_count;
    }
}

fn div_ceil(value: u64, divisor: u64) -> u64 {
    if value == 0 {
        0
    } else {
        1 + (value - 1) / divisor
    }
}

fn align_block(value: u64) -> u64 {
    div_ceil(value, V2_BLOCK_SIZE) * V2_BLOCK_SIZE
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{build_image_with_mode, inspect_image, ImageMode};
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn v2_layout_places_bitmap_extents_and_journal_after_v1_image() {
        let root = temp_dir("layout");
        fs::create_dir_all(root.join("var/lib/alpenglow")).unwrap();
        fs::write(root.join("var/lib/alpenglow/state.env"), vec![7_u8; 8192]).unwrap();
        let image_path = root.with_extension("glowfs");
        build_image_with_mode(&root, &image_path, ImageMode::Mutable).unwrap();
        let image = inspect_image(&image_path).unwrap();

        let layout = plan_v2_layout(
            &image.header,
            &image.entries,
            image.header.image_size + 1024 * 1024,
        )
        .unwrap();

        assert_eq!(layout.block_size, V2_BLOCK_SIZE);
        assert!(layout.bitmap_offset >= image.header.image_size);
        assert!(layout.extent_table_offset > layout.bitmap_offset);
        assert!(layout.journal_offset > layout.extent_table_offset);
        assert_eq!(layout.extents.len(), 1);
        assert!(layout.free_blocks > 0);
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image_path).unwrap();
    }

    #[test]
    fn v2_upgrade_writes_metadata_regions_and_marks_used_blocks() {
        let root = temp_dir("upgrade");
        fs::create_dir_all(root.join("var/lib/alpenglow")).unwrap();
        fs::write(root.join("var/lib/alpenglow/state.env"), vec![9_u8; 5000]).unwrap();
        let image_path = root.with_extension("glowfs");
        build_image_with_mode(&root, &image_path, ImageMode::Mutable).unwrap();
        let before = inspect_image(&image_path).unwrap();
        let target_size = before.header.image_size + 2 * 1024 * 1024;

        let layout = upgrade_image_to_v2(&image_path, target_size).unwrap();
        let after = inspect_image(&image_path).unwrap();
        let bytes = fs::read(&image_path).unwrap();

        assert_eq!(bytes.len() as u64, target_size);
        assert_ne!(after.header.flags & crate::FLAG_V2, 0);
        assert_eq!(
            &bytes[layout.superblock_offset as usize..layout.superblock_offset as usize + 8],
            V2_MAGIC
        );
        assert_eq!(
            used_bitmap_blocks(&bytes, &layout),
            layout.total_blocks - layout.free_blocks
        );
        assert!(layout.extents.iter().all(|extent| {
            let start = extent.physical_block * V2_BLOCK_SIZE;
            start >= layout.data_start && start < target_size
        }));
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image_path).unwrap();
    }

    fn used_bitmap_blocks(bytes: &[u8], layout: &V2Layout) -> u64 {
        let mut used = 0_u64;
        let start = layout.bitmap_offset as usize;
        let end = start + layout.bitmap_len as usize;
        for (byte_index, byte) in bytes[start..end].iter().enumerate() {
            for bit in 0..8 {
                let block = byte_index as u64 * 8 + bit;
                if block < layout.total_blocks && byte & (1 << bit) != 0 {
                    used += 1;
                }
            }
        }
        used
    }

    fn temp_dir(name: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "glowfsctl-v2-{name}-{}-{stamp}",
            std::process::id()
        ))
    }
}

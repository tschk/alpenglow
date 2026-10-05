//! Moves the backup GPT of a freshly written disk image to the end of the (larger) disk.
//!
//! A raw image carries its backup partition table at the end of the *image*. Written onto a
//! bigger disk that leaves the backup in the middle of the disk, which Linux warns about and
//! some firmware and tools reject. This is the same fix as `sgdisk -e`, and only that: it
//! touches headers, never partitions, and does nothing unless the existing table is fully valid.

use std::fs::OpenOptions;
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::Path;

use crate::InstallError;

const SECTOR: u64 = 512;
const SIGNATURE: &[u8; 8] = b"EFI PART";
const MIN_HEADER: usize = 92;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GptOutcome {
    /// The backup header and entries now live at the end of the disk.
    Moved {
        from_lba: u64,
        to_lba: u64,
    },
    AlreadyAtEnd,
    NotGpt,
    /// Left untouched, with the reason (damaged table, nowhere safe to put it, ...).
    Skipped(String),
}

fn le32(bytes: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap())
}

fn le64(bytes: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap())
}

fn put32(bytes: &mut [u8], at: usize, value: u32) {
    bytes[at..at + 4].copy_from_slice(&value.to_le_bytes());
}

fn put64(bytes: &mut [u8], at: usize, value: u64) {
    bytes[at..at + 8].copy_from_slice(&value.to_le_bytes());
}

/// CRC-32 of the header with its own checksum field treated as zero.
fn header_crc(header: &[u8]) -> u32 {
    let mut copy = header.to_vec();
    put32(&mut copy, 16, 0);
    crc32fast::hash(&copy)
}

fn skipped(reason: &str) -> io::Result<GptOutcome> {
    Ok(GptOutcome::Skipped(reason.to_string()))
}

fn read_sector<T: Read + Seek>(dev: &mut T, lba: u64) -> io::Result<[u8; SECTOR as usize]> {
    let mut sector = [0u8; SECTOR as usize];
    dev.seek(SeekFrom::Start(lba * SECTOR))?;
    dev.read_exact(&mut sector)?;
    Ok(sector)
}

/// Does the work on any seekable device of `disk_len` bytes. `image_len` is how many bytes the
/// image occupies; the new backup must start beyond it.
pub fn relocate_in<T: Read + Write + Seek>(
    dev: &mut T,
    disk_len: u64,
    image_len: u64,
) -> io::Result<GptOutcome> {
    if disk_len < 4 * SECTOR {
        return skipped("the disk is too small");
    }
    let primary = read_sector(dev, 1)?;
    if &primary[0..8] != SIGNATURE {
        return Ok(GptOutcome::NotGpt);
    }
    let header_size = le32(&primary, 12) as usize;
    if !(MIN_HEADER..=SECTOR as usize).contains(&header_size) {
        return skipped("unsupported GPT header size");
    }
    if header_crc(&primary[..header_size]) != le32(&primary, 16) {
        return skipped("the GPT header checksum is wrong");
    }
    if le64(&primary, 24) != 1 {
        return skipped("the primary GPT header is not at LBA 1");
    }
    let alternate = le64(&primary, 32);
    let entries_lba = le64(&primary, 72);
    let count = le32(&primary, 80) as u64;
    let entry_size = le32(&primary, 84) as u64;
    if count == 0
        || count > 4096
        || entry_size < 128
        || !entry_size.is_multiple_of(8)
        || entry_size > 4096
    {
        return skipped("unsupported GPT entry layout");
    }
    let entries_len = count * entry_size;
    let entries_sectors = entries_len.div_ceil(SECTOR);

    let mut entries = vec![0u8; entries_len as usize];
    dev.seek(SeekFrom::Start(entries_lba * SECTOR))?;
    dev.read_exact(&mut entries)?;
    if crc32fast::hash(&entries) != le32(&primary, 88) {
        return skipped("the GPT entries checksum is wrong");
    }

    let new_last = disk_len / SECTOR - 1;
    if alternate == new_last {
        return Ok(GptOutcome::AlreadyAtEnd);
    }
    if alternate > new_last {
        return skipped("the backup GPT lies beyond the end of this disk");
    }
    let new_entries_lba = new_last - entries_sectors;
    let new_last_usable = new_entries_lba - 1;
    let used_end = entries
        .chunks_exact(entry_size as usize)
        .filter(|entry| entry[..16].iter().any(|byte| *byte != 0))
        .map(|entry| le64(entry, 40))
        .max()
        .unwrap_or(0);
    if new_last_usable < used_end {
        return skipped("a partition would cross the new backup table");
    }
    if new_entries_lba * SECTOR < image_len {
        return skipped("the new backup table would overlap the written image");
    }

    // Backup first (the area is unused), then the primary in a single sector write.
    dev.seek(SeekFrom::Start(new_entries_lba * SECTOR))?;
    dev.write_all(&entries)?;
    let mut backup = primary[..header_size].to_vec();
    put64(&mut backup, 24, new_last);
    put64(&mut backup, 32, 1);
    put64(&mut backup, 48, new_last_usable);
    put64(&mut backup, 72, new_entries_lba);
    let crc = header_crc(&backup);
    put32(&mut backup, 16, crc);
    let mut backup_sector = [0u8; SECTOR as usize];
    backup_sector[..header_size].copy_from_slice(&backup);
    dev.seek(SeekFrom::Start(new_last * SECTOR))?;
    dev.write_all(&backup_sector)?;

    let mut updated = primary;
    put64(&mut updated, 32, new_last);
    put64(&mut updated, 48, new_last_usable);
    let crc = header_crc(&updated[..header_size]);
    put32(&mut updated, 16, crc);
    dev.seek(SeekFrom::Start(SECTOR))?;
    dev.write_all(&updated)?;

    // The protective MBR should cover the disk (capped at what 32 bits can hold).
    let mbr = read_sector(dev, 0)?;
    if mbr[510] == 0x55 && mbr[511] == 0xAA && mbr[446 + 4] == 0xEE && le32(&mbr, 446 + 8) == 1 {
        let mut mbr = mbr;
        let covered = (new_last).min(u64::from(u32::MAX)) as u32;
        put32(&mut mbr, 446 + 12, covered);
        dev.seek(SeekFrom::Start(0))?;
        dev.write_all(&mbr)?;
    }

    // Wipe the stale backup, but only where it really is one.
    let old = read_sector(dev, alternate)?;
    if &old[0..8] == SIGNATURE && alternate >= entries_sectors {
        let zeros = vec![0u8; ((entries_sectors + 1) * SECTOR) as usize];
        dev.seek(SeekFrom::Start((alternate - entries_sectors) * SECTOR))?;
        dev.write_all(&zeros)?;
    }
    dev.flush()?;
    Ok(GptOutcome::Moved {
        from_lba: alternate,
        to_lba: new_last,
    })
}

/// Logical sector size of an open device: 512 for regular files.
#[cfg(unix)]
fn logical_sector_size(file: &std::fs::File) -> u64 {
    use std::os::fd::AsRawFd;
    use std::os::unix::fs::FileTypeExt;
    const BLKSSZGET: u32 = 0x1268;
    let is_block = file
        .metadata()
        .map(|metadata| metadata.file_type().is_block_device())
        .unwrap_or(false);
    if !is_block {
        return SECTOR;
    }
    let mut size: libc::c_int = 0;
    let result = unsafe { libc::ioctl(file.as_raw_fd(), BLKSSZGET as _, &mut size) };
    if result == 0 && size > 0 {
        size as u64
    } else {
        SECTOR
    }
}

#[cfg(not(unix))]
fn logical_sector_size(_file: &std::fs::File) -> u64 {
    SECTOR
}

/// Moves the backup GPT on `target` (already holding `image_len` bytes of image) to the end of
/// the disk, then syncs.
pub fn relocate_backup_gpt(target: &Path, image_len: u64) -> Result<GptOutcome, InstallError> {
    let mut file = OpenOptions::new().read(true).write(true).open(target)?;
    let disk_len = file.seek(SeekFrom::End(0))?;
    let sector = logical_sector_size(&file);
    if sector != SECTOR {
        return Ok(GptOutcome::Skipped(format!(
            "the disk has {sector}-byte sectors"
        )));
    }
    let outcome = relocate_in(&mut file, disk_len, image_len)?;
    file.sync_all()?;
    Ok(outcome)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    const ENTRIES: u64 = 128;
    const ENTRY_SIZE: u64 = 128;
    const ENTRY_SECTORS: u64 = ENTRIES * ENTRY_SIZE / SECTOR;

    /// A valid GPT disk of `sectors` sectors with two partitions, written the way sgdisk lays it
    /// out (protective MBR, primary at LBA 1/2, backup entries then header at the end).
    fn build_gpt(sectors: u64) -> Vec<u8> {
        let mut disk = vec![0u8; (sectors * SECTOR) as usize];
        let last = sectors - 1;
        let mut entries = vec![0u8; (ENTRIES * ENTRY_SIZE) as usize];
        for (index, (first, end)) in [(2048u64, 4095u64), (4096, sectors - 40)]
            .iter()
            .enumerate()
        {
            let entry = &mut entries[index * ENTRY_SIZE as usize..][..ENTRY_SIZE as usize];
            entry[..16].copy_from_slice(&[
                0xAF, 0x3D, 0xC6, 0x0F, 0x83, 0x84, 0x72, 0x47, 0x8E, 0x79, 0x3D, 0x69, 0xD8, 0x47,
                0x7D, 0xE4,
            ]);
            entry[16..32].copy_from_slice(&[index as u8 + 1; 16]);
            put64(entry, 32, *first);
            put64(entry, 40, *end);
        }
        let make_header = |my: u64, alt: u64, entries_lba: u64| {
            let mut header = vec![0u8; 92];
            header[..8].copy_from_slice(SIGNATURE);
            put32(&mut header, 8, 0x0001_0000);
            put32(&mut header, 12, 92);
            put64(&mut header, 24, my);
            put64(&mut header, 32, alt);
            put64(&mut header, 40, 34);
            put64(&mut header, 48, last - ENTRY_SECTORS - 1);
            header[56..72].copy_from_slice(&[0x11; 16]);
            put64(&mut header, 72, entries_lba);
            put32(&mut header, 80, ENTRIES as u32);
            put32(&mut header, 84, ENTRY_SIZE as u32);
            put32(&mut header, 88, crc32fast::hash(&entries));
            let crc = header_crc(&header);
            put32(&mut header, 16, crc);
            header
        };
        // Protective MBR.
        disk[446 + 4] = 0xEE;
        put32(&mut disk, 446 + 8, 1);
        put32(&mut disk, 446 + 12, last as u32);
        disk[510] = 0x55;
        disk[511] = 0xAA;
        let primary = make_header(1, last, 2);
        disk[SECTOR as usize..][..92].copy_from_slice(&primary);
        disk[(2 * SECTOR) as usize..][..entries.len()].copy_from_slice(&entries);
        let backup_entries = last - ENTRY_SECTORS;
        disk[(backup_entries * SECTOR) as usize..][..entries.len()].copy_from_slice(&entries);
        let backup = make_header(last, 1, backup_entries);
        disk[(last * SECTOR) as usize..][..92].copy_from_slice(&backup);
        disk
    }

    /// Independent check of a whole disk: both headers valid, pointing at each other, entries
    /// identical and checksummed, last usable LBA consistent.
    fn assert_valid_gpt(disk: &[u8]) {
        let sectors = disk.len() as u64 / SECTOR;
        let last = sectors - 1;
        let sector = |lba: u64| &disk[(lba * SECTOR) as usize..][..SECTOR as usize];
        let primary = sector(1);
        let backup = sector(last);
        for (name, header, my, alt) in [("primary", primary, 1, last), ("backup", backup, last, 1)]
        {
            assert_eq!(&header[..8], SIGNATURE, "{name} signature");
            assert_eq!(header_crc(&header[..92]), le32(header, 16), "{name} crc");
            assert_eq!(le64(header, 24), my, "{name} my_lba");
            assert_eq!(le64(header, 32), alt, "{name} alternate");
            assert_eq!(
                le64(header, 48),
                last - ENTRY_SECTORS - 1,
                "{name} last usable"
            );
        }
        let entries_at =
            |lba: u64| &disk[(lba * SECTOR) as usize..][..(ENTRIES * ENTRY_SIZE) as usize];
        let primary_entries = entries_at(le64(primary, 72));
        let backup_entries = entries_at(le64(backup, 72));
        assert_eq!(le64(backup, 72), last - ENTRY_SECTORS);
        assert_eq!(primary_entries, backup_entries);
        assert_eq!(crc32fast::hash(primary_entries), le32(primary, 88));
        assert_eq!(crc32fast::hash(backup_entries), le32(backup, 88));
    }

    fn enlarge(image: &[u8], sectors: u64) -> Vec<u8> {
        let mut disk = image.to_vec();
        disk.resize((sectors * SECTOR) as usize, 0);
        disk
    }

    #[test]
    fn moves_the_backup_to_the_end_of_a_larger_disk() {
        let image = build_gpt(8192);
        assert_valid_gpt(&image);
        let image_len = image.len() as u64;
        let mut disk = enlarge(&image, 32768);
        let before_entries = disk[(2 * SECTOR) as usize..][..16384].to_vec();
        let outcome = {
            let mut cursor = Cursor::new(&mut disk);
            relocate_in(&mut cursor, 32768 * SECTOR, image_len).unwrap()
        };
        assert_eq!(
            outcome,
            GptOutcome::Moved {
                from_lba: 8191,
                to_lba: 32767
            }
        );
        assert_valid_gpt(&disk);
        // Partitions are untouched.
        assert_eq!(&disk[(2 * SECTOR) as usize..][..16384], &before_entries[..]);
        // The protective MBR now spans the disk.
        assert_eq!(le32(&disk, 446 + 12), 32767);
        // The stale backup header and entries are gone.
        let old_start = ((8191 - ENTRY_SECTORS) * SECTOR) as usize;
        assert!(disk[old_start..(8192 * SECTOR) as usize]
            .iter()
            .all(|b| *b == 0));
    }

    #[test]
    fn a_second_run_changes_nothing() {
        let image = build_gpt(8192);
        let mut disk = enlarge(&image, 20000);
        let len = disk.len() as u64;
        relocate_in(&mut Cursor::new(&mut disk), len, image.len() as u64).unwrap();
        let after_first = disk.clone();
        let outcome = relocate_in(&mut Cursor::new(&mut disk), len, image.len() as u64).unwrap();
        assert_eq!(outcome, GptOutcome::AlreadyAtEnd);
        assert_eq!(disk, after_first);
    }

    #[test]
    fn an_image_that_already_fills_the_disk_is_left_alone() {
        let image = build_gpt(8192);
        let mut disk = image.clone();
        let outcome = relocate_in(
            &mut Cursor::new(&mut disk),
            image.len() as u64,
            image.len() as u64,
        )
        .unwrap();
        assert_eq!(outcome, GptOutcome::AlreadyAtEnd);
        assert_eq!(disk, image);
    }

    #[test]
    fn non_gpt_data_is_reported_and_untouched() {
        let mut disk = vec![0x5Au8; (4096 * SECTOR) as usize];
        let before = disk.clone();
        let len = disk.len() as u64;
        let outcome = relocate_in(&mut Cursor::new(&mut disk), len, 1024).unwrap();
        assert_eq!(outcome, GptOutcome::NotGpt);
        assert_eq!(disk, before);
    }

    #[test]
    fn a_damaged_header_or_entries_table_is_never_modified() {
        let image = build_gpt(8192);
        // Flip a bit in the primary header (breaks its checksum) ...
        let mut bad_header = enlarge(&image, 20000);
        bad_header[(SECTOR + 40) as usize] ^= 1;
        // ... and in the entries (breaks the entries checksum).
        let mut bad_entries = enlarge(&image, 20000);
        bad_entries[(2 * SECTOR + 3) as usize] ^= 1;
        for mut disk in [bad_header, bad_entries] {
            let before = disk.clone();
            let len = disk.len() as u64;
            let outcome =
                relocate_in(&mut Cursor::new(&mut disk), len, image.len() as u64).unwrap();
            assert!(matches!(outcome, GptOutcome::Skipped(_)), "{outcome:?}");
            assert_eq!(disk, before);
        }
    }

    #[test]
    fn refuses_when_the_new_backup_would_overlap_the_image() {
        let image = build_gpt(8192);
        // Only 20 sectors bigger than the image: the new backup (33 sectors) cannot fit beyond it.
        let mut disk = enlarge(&image, 8192 + 20);
        let before = disk.clone();
        let len = disk.len() as u64;
        let outcome = relocate_in(&mut Cursor::new(&mut disk), len, image.len() as u64).unwrap();
        assert!(matches!(outcome, GptOutcome::Skipped(_)), "{outcome:?}");
        assert_eq!(disk, before);
    }

    #[test]
    fn refuses_a_disk_smaller_than_the_backup_location() {
        let image = build_gpt(8192);
        let mut disk = image[..(4096 * SECTOR) as usize].to_vec();
        let before = disk.clone();
        let len = disk.len() as u64;
        let outcome = relocate_in(&mut Cursor::new(&mut disk), len, 0).unwrap();
        assert!(matches!(outcome, GptOutcome::Skipped(_)), "{outcome:?}");
        assert_eq!(disk, before);
    }

    #[test]
    fn works_on_a_regular_file_target() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("disk.img");
        let image = build_gpt(4096);
        let disk = enlarge(&image, 10000);
        std::fs::write(&path, &disk).unwrap();
        let outcome = relocate_backup_gpt(&path, image.len() as u64).unwrap();
        assert_eq!(
            outcome,
            GptOutcome::Moved {
                from_lba: 4095,
                to_lba: 9999
            }
        );
        assert_valid_gpt(&std::fs::read(&path).unwrap());
    }
}

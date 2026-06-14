#![no_std]

#[repr(C)]
#[derive(Clone, Copy)]
pub struct SolfsDiskHeader {
    magic: [u8; 8],
    version: u32,
    entry_count: u32,
    entries_offset: u64,
    names_offset: u64,
    data_offset: u64,
    image_size: u64,
    flags: u64,
}

const MAGIC: [u8; 8] = *b"GLWFSV01";
const VERSION: u32 = 1;
const HEADER_LEN: u64 = 56;
const ENTRY_LEN: u64 = 92;

#[no_mangle]
pub extern "C" fn glowfs_rust_validate_header(header: SolfsDiskHeader) -> i32 {
    if header.magic != MAGIC {
        return -22;
    }
    if u32::from_le(header.version) != VERSION {
        return -22;
    }
    let entry_count = u32::from_le(header.entry_count) as u64;
    let entries_offset = u64::from_le(header.entries_offset);
    let names_offset = u64::from_le(header.names_offset);
    let data_offset = u64::from_le(header.data_offset);
    let image_size = u64::from_le(header.image_size);
    let entries_len = entry_count.saturating_mul(ENTRY_LEN);
    if entry_count == 0 {
        return -22;
    }
    if entries_offset != HEADER_LEN {
        return -22;
    }
    if entries_len / ENTRY_LEN != entry_count {
        return -22;
    }
    if names_offset < entries_offset.saturating_add(entries_len) {
        return -22;
    }
    if data_offset < names_offset {
        return -22;
    }
    if image_size < data_offset {
        return -22;
    }
    if image_size < names_offset {
        return -22;
    }
    0
}

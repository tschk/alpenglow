// SPDX-License-Identifier: GPL-2.0

//! GlowFS Rust core — header validation and metadata parsing.
//!
//! This module is compiled as part of the GlowFS kernel module.
//! It validates the on-disk header and provides safe parsing utilities.

#![no_std]

use core::mem;

/// On-disk GlowFS header (must match C `struct glowfs_disk_header`).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct GlowfsDiskHeader {
    magic: [u8; 8],
    version: u32,
    entry_count: u32,
    entries_offset: u64,
    names_offset: u64,
    data_offset: u64,
    image_size: u64,
    flags: u64,
}

const GLOWFS_MAGIC: [u8; 8] = *b"GLWFSV01";
const GLOWFS_VERSION: u32 = 1;
const GLOWFS_HEADER_LEN: u64 = mem::size_of::<GlowfsDiskHeader>() as u64;
const GLOWFS_ENTRY_LEN: u64 = 92;
const GLOWFS_MAX_ENTRIES: u32 = 65536;
const GLOWFS_MAX_NAMES_SIZE: u64 = 16 * 1024 * 1024;

/// Validate a GlowFS disk header. Returns 0 on success, negative errno on failure.
/// Called from C via `glowfs_rust_validate_header`.
#[no_mangle]
pub extern "C" fn glowfs_rust_validate_header(header: GlowfsDiskHeader) -> i32 {
    // Magic check
    if header.magic != GLOWFS_MAGIC {
        return -22; // -EINVAL
    }
    // Version check
    if u32::from_le(header.version) != GLOWFS_VERSION {
        return -22;
    }
    let entry_count = u32::from_le(header.entry_count);
    if entry_count == 0 || entry_count > GLOWFS_MAX_ENTRIES {
        return -22;
    }
    let entries_offset = u64::from_le(header.entries_offset);
    let names_offset = u64::from_le(header.names_offset);
    let data_offset = u64::from_le(header.data_offset);
    let image_size = u64::from_le(header.image_size);

    // Entry count overflow check
    let entry_count_u64 = entry_count as u64;
    let entries_len = match entry_count_u64.checked_mul(GLOWFS_ENTRY_LEN) {
        Some(v) => v,
        None => return -22,
    };

    // Layout validation: header < entries < names < data < image
    if entries_offset != GLOWFS_HEADER_LEN {
        return -22;
    }
    if names_offset < entries_offset.checked_add(entries_len).unwrap_or(u64::MAX) {
        return -22;
    }
    if data_offset < names_offset {
        return -22;
    }
    if image_size < data_offset {
        return -22;
    }

    // Names size must be reasonable
    let names_size = data_offset - names_offset;
    if names_size > GLOWFS_MAX_NAMES_SIZE {
        return -22;
    }

    0
}

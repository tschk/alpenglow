// Copyright 2024 Alpenglow Authors
// SPDX-License-Identifier: MPL-2.0
//
// Generic MMC/SD Driver
// Platform-agnostic SD/MMC controller implementation

use crate::traits::{DriverError, DriverResult, MmcBusWidth, MmcCardInfo, MmcCardType, MmcDriver};
// Removed unused imports

/// MMC command opcodes
pub mod cmd {
    pub const GO_IDLE_STATE: u32 = 0;
    pub const SEND_OP_COND: u32 = 1;
    pub const ALL_SEND_CID: u32 = 2;
    pub const SET_RELATIVE_ADDR: u32 = 3;
    pub const SET_DSR: u32 = 4;
    pub const SWITCH: u32 = 6;
    pub const SELECT_CARD: u32 = 7;
    pub const SEND_EXT_CSD: u32 = 8;
    pub const SEND_CSD: u32 = 9;
    pub const SEND_CID: u32 = 10;
    pub const STOP_TRANSMISSION: u32 = 12;
    pub const SEND_STATUS: u32 = 13;
    pub const SET_BLOCKLEN: u32 = 16;
    pub const READ_SINGLE_BLOCK: u32 = 17;
    pub const READ_MULTIPLE_BLOCK: u32 = 18;
    pub const WRITE_SINGLE_BLOCK: u32 = 24;
    pub const WRITE_MULTIPLE_BLOCK: u32 = 25;
    pub const ERASE_START: u32 = 32;
    pub const ERASE_END: u32 = 33;
    pub const ERASE: u32 = 38;
    pub const APP_CMD: u32 = 55;

    // SD Application commands (after APP_CMD)
    pub const SD_SET_BUS_WIDTH: u32 = 6;
    pub const SD_SEND_OP_COND: u32 = 41;
    pub const SD_SEND_SCR: u32 = 51;
}

/// MMC response types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MmcResponse {
    None,
    R1,  // Normal response
    R1b, // Normal response with busy
    R2,  // CID/CSD register
    R3,  // OCR register
    R6,  // Published RCA
    R7,  // Card interface condition
}

/// MMC command flags
#[derive(Debug, Clone, Copy)]
pub struct MmcCmdFlags {
    pub response: MmcResponse,
    pub data: bool,
    pub write: bool,
    pub multi_block: bool,
}

impl Default for MmcCmdFlags {
    fn default() -> Self {
        Self {
            response: MmcResponse::R1,
            data: false,
            write: false,
            multi_block: false,
        }
    }
}

/// MMC data transfer
pub struct MmcData<'a> {
    pub buffer: &'a mut [u8],
    pub block_size: u32,
    pub block_count: u32,
    pub write: bool,
}

/// Generic MMC host operations trait
/// Implement this for specific MMC controller hardware
pub trait MmcHostOps {
    /// Send a command
    fn send_cmd(&mut self, cmd: u32, arg: u32, flags: MmcCmdFlags) -> DriverResult<u32>;

    /// Read data after command
    fn read_data(&mut self, buffer: &mut [u8], block_size: u32) -> DriverResult<()>;

    /// Write data with command
    fn write_data(&mut self, data: &[u8], block_size: u32) -> DriverResult<()>;

    /// Set bus width
    fn set_bus_width(&mut self, width: MmcBusWidth) -> DriverResult<()>;

    /// Set clock frequency
    fn set_clock(&mut self, freq_hz: u32) -> DriverResult<()>;

    /// Wait for card to be ready
    fn wait_ready(&mut self, timeout_ms: u32) -> DriverResult<()>;

    /// Check if card is present
    fn card_detect(&self) -> bool;
}

/// Generic MMC driver using host operations
pub struct GenericMmcDriver<H: MmcHostOps> {
    host: H,
    card_info: Option<MmcCardInfo>,
    rca: u16,
}

impl<H: MmcHostOps> GenericMmcDriver<H> {
    pub fn new(host: H) -> Self {
        Self {
            host,
            card_info: None,
            rca: 0,
        }
    }

    /// Send CMD0 (GO_IDLE_STATE)
    fn go_idle(&mut self) -> DriverResult<()> {
        self.host.send_cmd(
            cmd::GO_IDLE_STATE,
            0,
            MmcCmdFlags {
                response: MmcResponse::None,
                ..Default::default()
            },
        )?;
        Ok(())
    }

    /// Check for SD card (CMD8)
    fn check_sd_card(&mut self) -> DriverResult<bool> {
        // CMD8 with check pattern 0xAA and voltage 2.7-3.6V
        let arg = 0x1AA;
        match self.host.send_cmd(
            8,
            arg,
            MmcCmdFlags {
                response: MmcResponse::R7,
                ..Default::default()
            },
        ) {
            Ok(resp) => {
                // Check pattern should be echoed back
                Ok((resp & 0xFF) == 0xAA)
            }
            Err(_) => Ok(false),
        }
    }

    /// Initialize SD card
    fn init_sd_card(&mut self, is_sdhc: bool) -> DriverResult<MmcCardType> {
        // ACMD41 to get OCR and check HCS (High Capacity Support)
        let arg = if is_sdhc { 0x40FF8000 } else { 0x00FF8000 };

        for _ in 0..100 {
            // Send APP_CMD first
            self.host.send_cmd(
                cmd::APP_CMD,
                0,
                MmcCmdFlags {
                    response: MmcResponse::R1,
                    ..Default::default()
                },
            )?;

            let ocr = self.host.send_cmd(
                cmd::SD_SEND_OP_COND,
                arg,
                MmcCmdFlags {
                    response: MmcResponse::R3,
                    ..Default::default()
                },
            )?;

            // Check if card is ready (bit 31)
            if (ocr & (1 << 31)) != 0 {
                // Check CCS (Card Capacity Status) bit 30
                let card_type = if (ocr & (1 << 30)) != 0 {
                    MmcCardType::SdHc
                } else {
                    MmcCardType::Sd
                };
                return Ok(card_type);
            }

            // Small delay before retry
            self.host.wait_ready(10)?;
        }

        Err(DriverError::Timeout)
    }

    /// Initialize eMMC
    fn init_emmc(&mut self) -> DriverResult<MmcCardType> {
        for _ in 0..100 {
            let ocr = self.host.send_cmd(
                cmd::SEND_OP_COND,
                0x40FF8080, // High capacity, sector mode
                MmcCmdFlags {
                    response: MmcResponse::R3,
                    ..Default::default()
                },
            )?;

            if (ocr & (1 << 31)) != 0 {
                return Ok(MmcCardType::Emmc);
            }

            self.host.wait_ready(10)?;
        }

        Err(DriverError::Timeout)
    }

    /// Get card identification (CMD2)
    fn get_cid(&mut self) -> DriverResult<[u32; 4]> {
        self.host.send_cmd(
            cmd::ALL_SEND_CID,
            0,
            MmcCmdFlags {
                response: MmcResponse::R2,
                ..Default::default()
            },
        )?;

        // R2 response is 128 bits, need multiple reads
        // For now, return placeholder
        Ok([0; 4])
    }

    /// Get relative card address (CMD3)
    fn get_rca(&mut self, is_sd: bool) -> DriverResult<u16> {
        if is_sd {
            // SD card publishes RCA
            let resp = self.host.send_cmd(
                cmd::SET_RELATIVE_ADDR,
                0,
                MmcCmdFlags {
                    response: MmcResponse::R6,
                    ..Default::default()
                },
            )?;
            Ok((resp >> 16) as u16)
        } else {
            // eMMC: we assign RCA
            let rca = 1u16;
            self.host.send_cmd(
                cmd::SET_RELATIVE_ADDR,
                (rca as u32) << 16,
                MmcCmdFlags {
                    response: MmcResponse::R1,
                    ..Default::default()
                },
            )?;
            Ok(rca)
        }
    }

    /// Select the card (CMD7)
    fn select_card(&mut self) -> DriverResult<()> {
        self.host.send_cmd(
            cmd::SELECT_CARD,
            (self.rca as u32) << 16,
            MmcCmdFlags {
                response: MmcResponse::R1b,
                ..Default::default()
            },
        )?;
        Ok(())
    }

    /// Set 4-bit bus width for SD
    fn set_sd_bus_width(&mut self) -> DriverResult<()> {
        // Send APP_CMD
        self.host.send_cmd(
            cmd::APP_CMD,
            (self.rca as u32) << 16,
            MmcCmdFlags {
                response: MmcResponse::R1,
                ..Default::default()
            },
        )?;

        // ACMD6: set bus width to 4-bit
        self.host.send_cmd(
            cmd::SD_SET_BUS_WIDTH,
            2, // 4-bit mode
            MmcCmdFlags {
                response: MmcResponse::R1,
                ..Default::default()
            },
        )?;

        self.host.set_bus_width(MmcBusWidth::Width4)?;
        Ok(())
    }

    /// Set block length (CMD16)
    fn set_block_length(&mut self, len: u32) -> DriverResult<()> {
        self.host.send_cmd(
            cmd::SET_BLOCKLEN,
            len,
            MmcCmdFlags {
                response: MmcResponse::R1,
                ..Default::default()
            },
        )?;
        Ok(())
    }

    /// Get card capacity from CSD
    fn get_capacity(&mut self, card_type: MmcCardType) -> u64 {
        // Would parse CSD register for actual capacity
        // For now, return common sizes
        match card_type {
            MmcCardType::Sd => 2 * 1024 * 1024 * 1024,    // 2GB
            MmcCardType::SdHc => 32 * 1024 * 1024 * 1024, // 32GB
            MmcCardType::SdXc => 64 * 1024 * 1024 * 1024, // 64GB
            MmcCardType::Emmc => 16 * 1024 * 1024 * 1024, // 16GB
            MmcCardType::Mmc => 512 * 1024 * 1024,        // 512MB
        }
    }
}

impl<H: MmcHostOps> MmcDriver for GenericMmcDriver<H> {
    fn init(&mut self) -> DriverResult<()> {
        if !self.host.card_detect() {
            return Err(DriverError::NotFound);
        }

        // Start with 400 kHz clock for initialization
        self.host.set_clock(400_000)?;
        self.host.set_bus_width(MmcBusWidth::Width1)?;

        // Send CMD0
        self.go_idle()?;

        // Try to identify card type
        let is_sd_v2 = self.check_sd_card()?;

        let card_type = if is_sd_v2 {
            self.init_sd_card(true)?
        } else {
            // Try SD v1.x first, then eMMC
            match self.init_sd_card(false) {
                Ok(t) => t,
                Err(_) => self.init_emmc()?,
            }
        };

        // Get CID
        self.get_cid()?;

        // Get RCA
        let is_sd = matches!(
            card_type,
            MmcCardType::Sd | MmcCardType::SdHc | MmcCardType::SdXc
        );
        self.rca = self.get_rca(is_sd)?;

        // Select card
        self.select_card()?;

        // Set bus width
        let bus_width = if is_sd {
            self.set_sd_bus_width()?;
            MmcBusWidth::Width4
        } else {
            // eMMC can use 8-bit
            self.host.set_bus_width(MmcBusWidth::Width8)?;
            MmcBusWidth::Width8
        };

        // Set block length (512 bytes standard)
        self.set_block_length(512)?;

        // Increase clock for normal operation
        let max_freq = match card_type {
            MmcCardType::SdHc | MmcCardType::SdXc => 50_000_000, // 50 MHz
            MmcCardType::Emmc => 52_000_000,                     // 52 MHz (HS mode)
            _ => 25_000_000,                                     // 25 MHz
        };
        self.host.set_clock(max_freq)?;

        // Store card info
        self.card_info = Some(MmcCardInfo {
            card_type,
            capacity_bytes: self.get_capacity(card_type),
            block_size: 512,
            bus_width,
            max_frequency: max_freq,
        });

        Ok(())
    }

    fn card_present(&self) -> bool {
        self.host.card_detect()
    }

    fn card_info(&self) -> DriverResult<MmcCardInfo> {
        self.card_info.clone().ok_or(DriverError::NotFound)
    }

    fn read_blocks(&mut self, start_block: u64, buffer: &mut [u8]) -> DriverResult<usize> {
        let info = self.card_info.as_ref().ok_or(DriverError::NotFound)?;
        let block_size = info.block_size as usize;

        if buffer.len() < block_size {
            return Err(DriverError::InvalidParam);
        }

        let block_count = buffer.len() / block_size;

        // For SDHC/SDXC, block address is used directly
        // For SD, byte address is used
        let addr = match info.card_type {
            MmcCardType::SdHc | MmcCardType::SdXc | MmcCardType::Emmc => start_block as u32,
            _ => (start_block * block_size as u64) as u32,
        };

        // Choose single or multi-block command
        let cmd = if block_count > 1 {
            cmd::READ_MULTIPLE_BLOCK
        } else {
            cmd::READ_SINGLE_BLOCK
        };

        // Send read command
        self.host.send_cmd(
            cmd,
            addr,
            MmcCmdFlags {
                response: MmcResponse::R1,
                data: true,
                write: false,
                multi_block: block_count > 1,
            },
        )?;

        // Read data
        for i in 0..block_count {
            let offset = i * block_size;
            self.host
                .read_data(&mut buffer[offset..offset + block_size], block_size as u32)?;
        }

        // Stop transmission for multi-block
        if block_count > 1 {
            self.host.send_cmd(
                cmd::STOP_TRANSMISSION,
                0,
                MmcCmdFlags {
                    response: MmcResponse::R1b,
                    ..Default::default()
                },
            )?;
        }

        Ok(block_count * block_size)
    }

    fn write_blocks(&mut self, start_block: u64, data: &[u8]) -> DriverResult<usize> {
        let info = self.card_info.as_ref().ok_or(DriverError::NotFound)?;
        let block_size = info.block_size as usize;

        if data.len() < block_size {
            return Err(DriverError::InvalidParam);
        }

        let block_count = data.len() / block_size;

        let addr = match info.card_type {
            MmcCardType::SdHc | MmcCardType::SdXc | MmcCardType::Emmc => start_block as u32,
            _ => (start_block * block_size as u64) as u32,
        };

        let cmd = if block_count > 1 {
            cmd::WRITE_MULTIPLE_BLOCK
        } else {
            cmd::WRITE_SINGLE_BLOCK
        };

        // Send write command
        self.host.send_cmd(
            cmd,
            addr,
            MmcCmdFlags {
                response: MmcResponse::R1,
                data: true,
                write: true,
                multi_block: block_count > 1,
            },
        )?;

        // Write data
        for i in 0..block_count {
            let offset = i * block_size;
            self.host
                .write_data(&data[offset..offset + block_size], block_size as u32)?;
        }

        // Stop transmission for multi-block
        if block_count > 1 {
            self.host.send_cmd(
                cmd::STOP_TRANSMISSION,
                0,
                MmcCmdFlags {
                    response: MmcResponse::R1b,
                    ..Default::default()
                },
            )?;
        }

        // Wait for write to complete
        self.host.wait_ready(500)?;

        Ok(block_count * block_size)
    }

    fn erase_blocks(&mut self, start_block: u64, block_count: u64) -> DriverResult<()> {
        let info = self.card_info.as_ref().ok_or(DriverError::NotFound)?;

        let start_addr = match info.card_type {
            MmcCardType::SdHc | MmcCardType::SdXc | MmcCardType::Emmc => start_block as u32,
            _ => (start_block * info.block_size as u64) as u32,
        };

        let end_block = start_block + block_count - 1;
        let end_addr = match info.card_type {
            MmcCardType::SdHc | MmcCardType::SdXc | MmcCardType::Emmc => end_block as u32,
            _ => (end_block * info.block_size as u64) as u32,
        };

        // Set erase start
        self.host.send_cmd(
            cmd::ERASE_START,
            start_addr,
            MmcCmdFlags {
                response: MmcResponse::R1,
                ..Default::default()
            },
        )?;

        // Set erase end
        self.host.send_cmd(
            cmd::ERASE_END,
            end_addr,
            MmcCmdFlags {
                response: MmcResponse::R1,
                ..Default::default()
            },
        )?;

        // Execute erase
        self.host.send_cmd(
            cmd::ERASE,
            0,
            MmcCmdFlags {
                response: MmcResponse::R1b,
                ..Default::default()
            },
        )?;

        // Wait for erase to complete
        self.host.wait_ready(5000)?;

        Ok(())
    }

    fn flush(&mut self) -> DriverResult<()> {
        // Ensure all writes are complete
        self.host.wait_ready(500)
    }
}

// ============================================================================
// Block device wrapper for filesystem support
// ============================================================================

/// Block device interface for filesystem layers
pub trait BlockDevice {
    /// Read sectors
    fn read(&mut self, sector: u64, buffer: &mut [u8]) -> DriverResult<()>;

    /// Write sectors
    fn write(&mut self, sector: u64, data: &[u8]) -> DriverResult<()>;

    /// Get sector size in bytes
    fn sector_size(&self) -> u32;

    /// Get total sector count
    fn sector_count(&self) -> u64;

    /// Sync/flush
    fn sync(&mut self) -> DriverResult<()>;
}

impl<H: MmcHostOps> BlockDevice for GenericMmcDriver<H> {
    fn read(&mut self, sector: u64, buffer: &mut [u8]) -> DriverResult<()> {
        self.read_blocks(sector, buffer)?;
        Ok(())
    }

    fn write(&mut self, sector: u64, data: &[u8]) -> DriverResult<()> {
        self.write_blocks(sector, data)?;
        Ok(())
    }

    fn sector_size(&self) -> u32 {
        self.card_info.as_ref().map(|i| i.block_size).unwrap_or(512)
    }

    fn sector_count(&self) -> u64 {
        self.card_info
            .as_ref()
            .map(|i| i.capacity_bytes / i.block_size as u64)
            .unwrap_or(0)
    }

    fn sync(&mut self) -> DriverResult<()> {
        self.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mmc_cmd_flags_default() {
        let flags = MmcCmdFlags::default();
        assert_eq!(flags.response, MmcResponse::R1);
        assert!(!flags.data);
        assert!(!flags.write);
    }
}

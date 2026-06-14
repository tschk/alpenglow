// Copyright 2024 Alpenglow Authors
// SPDX-License-Identifier: MPL-2.0
//
// Generic GPIO Driver
// Platform-agnostic GPIO implementation using MMIO

use crate::traits::{DriverError, DriverResult, GpioConfig, GpioDirection, GpioDriver, GpioPull};

/// Register offsets for generic GPIO controller
/// These match common ARM SoC GPIO controllers (Allwinner, Rockchip, etc.)
pub mod regs {
    /// Data register - read/write pin values
    pub const GPIO_DATA: u32 = 0x00;
    /// Direction register - 0=input, 1=output
    pub const GPIO_DIR: u32 = 0x04;
    /// Pull-up/down configuration
    pub const GPIO_PULL: u32 = 0x1C;
    /// Alternate function select
    pub const GPIO_ALT: u32 = 0x00; // Multiplexed with data on many SoCs
    /// Interrupt enable
    pub const GPIO_INT_EN: u32 = 0x20;
    /// Interrupt status
    pub const GPIO_INT_STA: u32 = 0x24;
}

/// Generic GPIO bank (group of pins)
pub struct GpioBank {
    /// Base address for this bank's registers
    base: *mut u32,
    /// Number of pins in this bank
    pin_count: u32,
    /// Pin offset within the bank (for multi-function pins)
    pin_offset: u32,
    /// Bits per pin for configuration (1, 2, or 4)
    bits_per_pin: u32,
}

impl GpioBank {
    /// Create a new GPIO bank
    ///
    /// # Safety
    /// The caller must ensure `base` points to valid MMIO registers
    pub unsafe fn new(base: usize, pin_count: u32) -> Self {
        Self {
            base: base as *mut u32,
            pin_count,
            pin_offset: 0,
            bits_per_pin: 1,
        }
    }

    /// Create with custom configuration
    ///
    /// # Safety
    /// The caller must ensure `base` points to valid MMIO registers
    pub unsafe fn new_with_config(
        base: usize,
        pin_count: u32,
        pin_offset: u32,
        bits_per_pin: u32,
    ) -> Self {
        Self {
            base: base as *mut u32,
            pin_count,
            pin_offset,
            bits_per_pin,
        }
    }

    #[inline]
    fn read_reg(&self, offset: u32) -> u32 {
        unsafe { core::ptr::read_volatile(self.base.add((offset / 4) as usize)) }
    }

    #[inline]
    fn write_reg(&self, offset: u32, value: u32) {
        unsafe { core::ptr::write_volatile(self.base.add((offset / 4) as usize), value) }
    }

    #[inline]
    fn modify_reg(&self, offset: u32, mask: u32, value: u32) {
        let current = self.read_reg(offset);
        self.write_reg(offset, (current & !mask) | (value & mask));
    }

    fn validate_pin(&self, pin: u32) -> DriverResult<()> {
        if pin >= self.pin_count {
            Err(DriverError::InvalidParam)
        } else {
            Ok(())
        }
    }

    fn pin_mask(&self, pin: u32) -> u32 {
        1 << (pin + self.pin_offset)
    }
}

impl GpioDriver for GpioBank {
    fn pin_count(&self) -> u32 {
        self.pin_count
    }

    fn configure(&mut self, pin: u32, config: &GpioConfig) -> DriverResult<()> {
        self.validate_pin(pin)?;

        let mask = self.pin_mask(pin);

        // Set direction
        match config.direction {
            GpioDirection::Input => {
                self.modify_reg(regs::GPIO_DIR, mask, 0);
            }
            GpioDirection::Output => {
                self.modify_reg(regs::GPIO_DIR, mask, mask);
                // Set initial value
                if config.initial_value {
                    self.modify_reg(regs::GPIO_DATA, mask, mask);
                } else {
                    self.modify_reg(regs::GPIO_DATA, mask, 0);
                }
            }
        }

        // Set pull configuration
        // Most SoCs use 2 bits per pin for pull config
        let pull_offset = (pin * 2) % 32;
        let pull_reg = regs::GPIO_PULL + ((pin * 2) / 32) * 4;
        let pull_mask = 0x3 << pull_offset;
        let pull_val = match config.pull {
            GpioPull::None => 0,
            GpioPull::Up => 1,
            GpioPull::Down => 2,
        } << pull_offset;

        self.modify_reg(pull_reg, pull_mask, pull_val);

        Ok(())
    }

    fn read(&self, pin: u32) -> DriverResult<bool> {
        self.validate_pin(pin)?;
        let mask = self.pin_mask(pin);
        Ok((self.read_reg(regs::GPIO_DATA) & mask) != 0)
    }

    fn write(&mut self, pin: u32, value: bool) -> DriverResult<()> {
        self.validate_pin(pin)?;
        let mask = self.pin_mask(pin);
        if value {
            self.modify_reg(regs::GPIO_DATA, mask, mask);
        } else {
            self.modify_reg(regs::GPIO_DATA, mask, 0);
        }
        Ok(())
    }

    fn set_alt_function(&mut self, pin: u32, function: u32) -> DriverResult<()> {
        self.validate_pin(pin)?;

        // Most ARM SoCs use 4 bits per pin for alternate function
        // Stored in CFG registers (typically at offset 0x00, 0x04, 0x08, 0x0C for 8 pins each)
        let pins_per_reg = 32 / self.bits_per_pin;
        let cfg_reg = (pin / pins_per_reg) * 4;
        let cfg_offset = (pin % pins_per_reg) * self.bits_per_pin;
        let field_mask = (1u32 << self.bits_per_pin) - 1;
        let cfg_mask = field_mask << cfg_offset;
        let cfg_val = (function & field_mask) << cfg_offset;

        self.modify_reg(cfg_reg, cfg_mask, cfg_val);

        Ok(())
    }
}

/// Multi-bank GPIO controller
pub struct GpioController {
    banks: alloc::vec::Vec<GpioBank>,
    pins_per_bank: u32,
}

impl GpioController {
    /// Create a new GPIO controller with multiple banks
    pub fn new(pins_per_bank: u32) -> Self {
        Self {
            banks: alloc::vec::Vec::new(),
            pins_per_bank,
        }
    }

    /// Add a GPIO bank
    ///
    /// # Safety
    /// The caller must ensure the base address is valid MMIO
    pub unsafe fn add_bank(&mut self, base: usize, pin_count: u32) {
        self.banks.push(GpioBank::new(base, pin_count));
    }

    fn get_bank_and_pin(&self, pin: u32) -> DriverResult<(&GpioBank, u32)> {
        let bank_idx = (pin / self.pins_per_bank) as usize;
        let pin_in_bank = pin % self.pins_per_bank;

        self.banks
            .get(bank_idx)
            .map(|b| (b, pin_in_bank))
            .ok_or(DriverError::InvalidParam)
    }

    fn get_bank_and_pin_mut(&mut self, pin: u32) -> DriverResult<(&mut GpioBank, u32)> {
        let bank_idx = (pin / self.pins_per_bank) as usize;
        let pin_in_bank = pin % self.pins_per_bank;

        self.banks
            .get_mut(bank_idx)
            .map(|b| (b, pin_in_bank))
            .ok_or(DriverError::InvalidParam)
    }
}

impl GpioDriver for GpioController {
    fn pin_count(&self) -> u32 {
        self.banks.iter().map(|b| b.pin_count).sum()
    }

    fn configure(&mut self, pin: u32, config: &GpioConfig) -> DriverResult<()> {
        let (bank, pin_in_bank) = self.get_bank_and_pin_mut(pin)?;
        bank.configure(pin_in_bank, config)
    }

    fn read(&self, pin: u32) -> DriverResult<bool> {
        let (bank, pin_in_bank) = self.get_bank_and_pin(pin)?;
        bank.read(pin_in_bank)
    }

    fn write(&mut self, pin: u32, value: bool) -> DriverResult<()> {
        let (bank, pin_in_bank) = self.get_bank_and_pin_mut(pin)?;
        bank.write(pin_in_bank, value)
    }

    fn set_alt_function(&mut self, pin: u32, function: u32) -> DriverResult<()> {
        let (bank, pin_in_bank) = self.get_bank_and_pin_mut(pin)?;
        bank.set_alt_function(pin_in_bank, function)
    }
}

// ============================================================================
// Allwinner-specific GPIO implementation
// ============================================================================

/// Allwinner GPIO (PIO) controller
/// Used on A527, H616, H6, A64, etc.
pub struct AllwinnerGpio {
    base: *mut u32,
    bank_count: u32,
}

impl AllwinnerGpio {
    /// Pins per bank on Allwinner SoCs
    pub const PINS_PER_BANK: u32 = 32;

    /// Register size per bank
    pub const BANK_SIZE: u32 = 0x24;

    /// Create a new Allwinner GPIO controller
    ///
    /// # Safety
    /// The caller must ensure `base` is the valid PIO base address
    pub unsafe fn new(base: usize, bank_count: u32) -> Self {
        let _ = (aw_regs::DRV0, aw_regs::DRV1);
        Self {
            base: base as *mut u32,
            bank_count,
        }
    }

    fn bank_base(&self, bank: u32) -> *mut u32 {
        unsafe { self.base.add((bank * Self::BANK_SIZE / 4) as usize) }
    }

    #[inline]
    fn read_bank_reg(&self, bank: u32, offset: u32) -> u32 {
        unsafe {
            let reg = self.bank_base(bank).add((offset / 4) as usize);
            core::ptr::read_volatile(reg)
        }
    }

    #[inline]
    fn write_bank_reg(&self, bank: u32, offset: u32, value: u32) {
        unsafe {
            let reg = self.bank_base(bank).add((offset / 4) as usize);
            core::ptr::write_volatile(reg, value);
        }
    }

    fn validate(&self, pin: u32) -> DriverResult<(u32, u32)> {
        let bank = pin / Self::PINS_PER_BANK;
        let pin_in_bank = pin % Self::PINS_PER_BANK;

        if bank >= self.bank_count || pin_in_bank >= Self::PINS_PER_BANK {
            return Err(DriverError::InvalidParam);
        }

        Ok((bank, pin_in_bank))
    }
}

/// Allwinner GPIO register offsets
mod aw_regs {
    pub const CFG0: u32 = 0x00; // Config for pins 0-7
    pub const CFG1: u32 = 0x04; // Config for pins 8-15
    pub const CFG2: u32 = 0x08; // Config for pins 16-23
    pub const CFG3: u32 = 0x0C; // Config for pins 24-31
    pub const DATA: u32 = 0x10; // Data register
    pub const DRV0: u32 = 0x14; // Drive strength 0-15
    pub const DRV1: u32 = 0x18; // Drive strength 16-31
    pub const PULL0: u32 = 0x1C; // Pull config 0-15
    pub const PULL1: u32 = 0x20; // Pull config 16-31
}

impl GpioDriver for AllwinnerGpio {
    fn pin_count(&self) -> u32 {
        self.bank_count * Self::PINS_PER_BANK
    }

    fn configure(&mut self, pin: u32, config: &GpioConfig) -> DriverResult<()> {
        let (bank, pin_in_bank) = self.validate(pin)?;

        // Set function (0=input, 1=output for basic GPIO)
        let cfg_reg = match pin_in_bank / 8 {
            0 => aw_regs::CFG0,
            1 => aw_regs::CFG1,
            2 => aw_regs::CFG2,
            3 => aw_regs::CFG3,
            _ => return Err(DriverError::InvalidParam),
        };

        let cfg_offset = (pin_in_bank % 8) * 4;
        let cfg_mask = 0xF << cfg_offset;
        let cfg_val = match config.direction {
            GpioDirection::Input => 0,
            GpioDirection::Output => 1,
        } << cfg_offset;

        let current = self.read_bank_reg(bank, cfg_reg);
        self.write_bank_reg(bank, cfg_reg, (current & !cfg_mask) | cfg_val);

        // Set initial value for outputs
        if config.direction == GpioDirection::Output {
            let data = self.read_bank_reg(bank, aw_regs::DATA);
            let mask = 1 << pin_in_bank;
            if config.initial_value {
                self.write_bank_reg(bank, aw_regs::DATA, data | mask);
            } else {
                self.write_bank_reg(bank, aw_regs::DATA, data & !mask);
            }
        }

        // Set pull configuration
        let pull_reg = if pin_in_bank < 16 {
            aw_regs::PULL0
        } else {
            aw_regs::PULL1
        };
        let pull_offset = (pin_in_bank % 16) * 2;
        let pull_mask = 0x3 << pull_offset;
        let pull_val = match config.pull {
            GpioPull::None => 0,
            GpioPull::Up => 1,
            GpioPull::Down => 2,
        } << pull_offset;

        let current = self.read_bank_reg(bank, pull_reg);
        self.write_bank_reg(bank, pull_reg, (current & !pull_mask) | pull_val);

        Ok(())
    }

    fn read(&self, pin: u32) -> DriverResult<bool> {
        let (bank, pin_in_bank) = self.validate(pin)?;
        let data = self.read_bank_reg(bank, aw_regs::DATA);
        Ok((data & (1 << pin_in_bank)) != 0)
    }

    fn write(&mut self, pin: u32, value: bool) -> DriverResult<()> {
        let (bank, pin_in_bank) = self.validate(pin)?;
        let data = self.read_bank_reg(bank, aw_regs::DATA);
        let mask = 1 << pin_in_bank;

        if value {
            self.write_bank_reg(bank, aw_regs::DATA, data | mask);
        } else {
            self.write_bank_reg(bank, aw_regs::DATA, data & !mask);
        }

        Ok(())
    }

    fn set_alt_function(&mut self, pin: u32, function: u32) -> DriverResult<()> {
        let (bank, pin_in_bank) = self.validate(pin)?;

        let cfg_reg = match pin_in_bank / 8 {
            0 => aw_regs::CFG0,
            1 => aw_regs::CFG1,
            2 => aw_regs::CFG2,
            3 => aw_regs::CFG3,
            _ => return Err(DriverError::InvalidParam),
        };

        let cfg_offset = (pin_in_bank % 8) * 4;
        let cfg_mask = 0xF << cfg_offset;
        let cfg_val = (function & 0xF) << cfg_offset;

        let current = self.read_bank_reg(bank, cfg_reg);
        self.write_bank_reg(bank, cfg_reg, (current & !cfg_mask) | cfg_val);

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gpio_config_default() {
        let config = GpioConfig::default();
        assert_eq!(config.direction, GpioDirection::Input);
        assert_eq!(config.pull, GpioPull::None);
        assert!(!config.initial_value);
    }
}

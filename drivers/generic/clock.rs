// Copyright 2024 Soliloquy Authors
// SPDX-License-Identifier: MPL-2.0
//
// Generic Clock Driver
// Platform-agnostic clock controller implementation

use crate::traits::{ClockDriver, ClockId, ClockRate, DriverError, DriverResult};
use alloc::vec::Vec;

/// Clock source types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClockSource {
    /// Fixed crystal oscillator
    Crystal,
    /// Phase-locked loop
    Pll,
    /// Derived from parent clock
    Derived,
    /// External clock input
    External,
}

/// Clock descriptor
#[derive(Debug, Clone)]
pub struct ClockDesc {
    pub id: ClockId,
    pub name: &'static str,
    pub source: ClockSource,
    pub parent: Option<ClockId>,
    pub min_rate: ClockRate,
    pub max_rate: ClockRate,
    pub default_rate: ClockRate,
}

/// Generic clock register layout
pub mod regs {
    /// Clock gate register (enable/disable)
    pub const CLK_GATE: u32 = 0x00;
    /// Clock divider register
    pub const CLK_DIV: u32 = 0x04;
    /// Clock source select register
    pub const CLK_SEL: u32 = 0x08;
    /// PLL configuration register
    pub const PLL_CFG: u32 = 0x10;
    /// PLL control register
    pub const PLL_CTRL: u32 = 0x14;
}

/// Clock state tracking
struct ClockState {
    enabled: bool,
    rate: ClockRate,
    parent: Option<ClockId>,
}

/// Generic clock controller
pub struct GenericClockController {
    base: *mut u32,
    clocks: Vec<ClockDesc>,
    states: Vec<ClockState>,
    parent_rate: ClockRate,
}

impl GenericClockController {
    /// Create a new clock controller
    ///
    /// # Safety
    /// The caller must ensure `base` points to valid CCU MMIO registers
    pub unsafe fn new(base: usize, parent_rate: ClockRate) -> Self {
        Self {
            base: base as *mut u32,
            clocks: Vec::new(),
            states: Vec::new(),
            parent_rate,
        }
    }

    /// Register a clock
    pub fn register_clock(&mut self, desc: ClockDesc) {
        let state = ClockState {
            enabled: false,
            rate: desc.default_rate,
            parent: desc.parent,
        };
        self.clocks.push(desc);
        self.states.push(state);
    }

    fn find_clock_idx(&self, id: ClockId) -> DriverResult<usize> {
        self.clocks
            .iter()
            .position(|c| c.id == id)
            .ok_or(DriverError::NotFound)
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

    /// Calculate divider for target rate
    fn calc_divider(&self, parent_rate: ClockRate, target: ClockRate) -> u32 {
        if target.0 == 0 {
            return 1;
        }
        let div = parent_rate.0 / target.0;
        div.max(1) as u32
    }
}

impl ClockDriver for GenericClockController {
    fn enable(&mut self, clock: ClockId) -> DriverResult<()> {
        let idx = self.find_clock_idx(clock)?;

        // Enable parent first if needed
        if let Some(parent_id) = self.states[idx].parent {
            self.enable(parent_id)?;
        }

        // Set gate bit (assumes bit position = clock ID)
        let gate_bit = 1 << (clock.0 % 32);
        let gate_reg = regs::CLK_GATE + (clock.0 / 32) * 4;
        self.modify_reg(gate_reg, gate_bit, gate_bit);

        self.states[idx].enabled = true;
        Ok(())
    }

    fn disable(&mut self, clock: ClockId) -> DriverResult<()> {
        let idx = self.find_clock_idx(clock)?;

        // Clear gate bit
        let gate_bit = 1 << (clock.0 % 32);
        let gate_reg = regs::CLK_GATE + (clock.0 / 32) * 4;
        self.modify_reg(gate_reg, gate_bit, 0);

        self.states[idx].enabled = false;
        Ok(())
    }

    fn is_enabled(&self, clock: ClockId) -> DriverResult<bool> {
        let idx = self.find_clock_idx(clock)?;
        Ok(self.states[idx].enabled)
    }

    fn get_rate(&self, clock: ClockId) -> DriverResult<ClockRate> {
        let idx = self.find_clock_idx(clock)?;
        Ok(self.states[idx].rate)
    }

    fn set_rate(&mut self, clock: ClockId, rate: ClockRate) -> DriverResult<ClockRate> {
        let idx = self.find_clock_idx(clock)?;
        let desc = &self.clocks[idx];

        // Clamp to valid range
        let target_rate = ClockRate(rate.0.clamp(desc.min_rate.0, desc.max_rate.0));

        // Get parent rate
        let parent_rate = if let Some(parent_id) = self.states[idx].parent {
            self.get_rate(parent_id)?
        } else {
            self.parent_rate
        };

        // Calculate and set divider
        let divider = self.calc_divider(parent_rate, target_rate);
        let actual_rate = ClockRate(parent_rate.0 / divider as u64);

        // Write divider (assumes simple divider register per clock)
        let div_reg = regs::CLK_DIV + clock.0 * 4;
        self.write_reg(div_reg, divider - 1);

        self.states[idx].rate = actual_rate;
        Ok(actual_rate)
    }

    fn get_parent(&self, clock: ClockId) -> DriverResult<Option<ClockId>> {
        let idx = self.find_clock_idx(clock)?;
        Ok(self.states[idx].parent)
    }

    fn set_parent(&mut self, clock: ClockId, parent: ClockId) -> DriverResult<()> {
        let idx = self.find_clock_idx(clock)?;

        // Verify parent exists
        self.find_clock_idx(parent)?;

        self.states[idx].parent = Some(parent);
        Ok(())
    }
}

// ============================================================================
// Allwinner CCU Implementation
// ============================================================================

/// Allwinner PLL types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AllwinnerPllType {
    /// Simple PLL: out = (in * N) / M
    Simple,
    /// Fractional PLL: out = (in * (N + K)) / (M * P)
    Fractional,
    /// Integer PLL with post divider
    Integer,
}

/// Allwinner CCU (Clock Control Unit)
pub struct AllwinnerCcu {
    base: *mut u32,
    hosc_rate: ClockRate, // 24 MHz crystal
    losc_rate: ClockRate, // 32.768 kHz RTC crystal
}

/// Allwinner A527 CCU register offsets
pub mod aw_ccu_regs {
    // PLLs
    pub const PLL_CPU: u32 = 0x000;
    pub const PLL_DDR: u32 = 0x010;
    pub const PLL_PERIPH0: u32 = 0x020;
    pub const PLL_PERIPH1: u32 = 0x028;
    pub const PLL_GPU: u32 = 0x030;
    pub const PLL_VIDEO0: u32 = 0x040;
    pub const PLL_VIDEO1: u32 = 0x048;
    pub const PLL_VE: u32 = 0x058;
    pub const PLL_AUDIO: u32 = 0x078;

    // Bus gates
    pub const BUS_CLK_GATE0: u32 = 0x800;
    pub const BUS_CLK_GATE1: u32 = 0x804;
    pub const BUS_CLK_GATE2: u32 = 0x808;
    pub const BUS_CLK_GATE3: u32 = 0x80C;

    // Module clocks
    pub const MMC0_CLK: u32 = 0x830;
    pub const MMC1_CLK: u32 = 0x834;
    pub const MMC2_CLK: u32 = 0x838;
    pub const UART_CLK: u32 = 0x90C;
    pub const SPI_CLK: u32 = 0x940;

    // Reset registers
    pub const BUS_RST0: u32 = 0x1000;
    pub const BUS_RST1: u32 = 0x1004;
    pub const BUS_RST2: u32 = 0x1008;
}

impl AllwinnerCcu {
    /// Standard crystal frequencies
    pub const HOSC_24MHZ: ClockRate = ClockRate::mhz(24);
    pub const LOSC_32KHZ: ClockRate = ClockRate(32768);

    /// Create a new Allwinner CCU driver
    ///
    /// # Safety
    /// The caller must ensure `base` points to the CCU registers
    pub unsafe fn new(base: usize) -> Self {
        Self {
            base: base as *mut u32,
            hosc_rate: Self::HOSC_24MHZ,
            losc_rate: Self::LOSC_32KHZ,
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

    /// Calculate PLL output frequency
    /// Formula: Fout = Fin * N / (M * P)
    fn calc_pll_rate(&self, reg_val: u32) -> ClockRate {
        let n = ((reg_val >> 8) & 0xFF) + 1;
        let m = (reg_val & 0x1) + 1;
        let p = ((reg_val >> 16) & 0x3) + 1;

        let rate = self.hosc_rate.0 * n as u64 / (m as u64 * p as u64);
        ClockRate(rate)
    }

    /// Get PLL CPU rate
    pub fn get_cpu_pll_rate(&self) -> ClockRate {
        let reg = self.read_reg(aw_ccu_regs::PLL_CPU);
        self.calc_pll_rate(reg)
    }

    /// Get PLL PERIPH0 rate
    pub fn get_periph0_pll_rate(&self) -> ClockRate {
        let reg = self.read_reg(aw_ccu_regs::PLL_PERIPH0);
        // PERIPH0 is typically 2x the basic rate
        let base_rate = self.calc_pll_rate(reg);
        ClockRate(base_rate.0 * 2)
    }

    pub fn get_losc_rate(&self) -> ClockRate {
        self.losc_rate
    }

    /// Enable a bus clock gate
    pub fn enable_bus_gate(&mut self, gate_reg: u32, bit: u32) {
        let val = self.read_reg(gate_reg);
        self.write_reg(gate_reg, val | (1 << bit));
    }

    /// Disable a bus clock gate
    pub fn disable_bus_gate(&mut self, gate_reg: u32, bit: u32) {
        let val = self.read_reg(gate_reg);
        self.write_reg(gate_reg, val & !(1 << bit));
    }

    /// Assert a reset
    pub fn assert_reset(&mut self, rst_reg: u32, bit: u32) {
        let val = self.read_reg(rst_reg);
        self.write_reg(rst_reg, val & !(1 << bit));
    }

    /// Deassert a reset
    pub fn deassert_reset(&mut self, rst_reg: u32, bit: u32) {
        let val = self.read_reg(rst_reg);
        self.write_reg(rst_reg, val | (1 << bit));
    }

    /// Configure MMC clock
    pub fn configure_mmc_clock(
        &mut self,
        mmc_idx: u32,
        rate: ClockRate,
    ) -> DriverResult<ClockRate> {
        if mmc_idx > 2 {
            return Err(DriverError::InvalidParam);
        }

        let clk_reg = match mmc_idx {
            0 => aw_ccu_regs::MMC0_CLK,
            1 => aw_ccu_regs::MMC1_CLK,
            2 => aw_ccu_regs::MMC2_CLK,
            _ => unreachable!(),
        };

        // Use PERIPH0(2x) as source
        let src_rate = self.get_periph0_pll_rate();

        // Calculate dividers (N and M)
        let target = rate.0;
        let mut best_n = 0u32;
        let mut best_m = 0u32;
        let mut best_rate = 0u64;

        for n in 0..4u32 {
            for m in 1..16u32 {
                let actual = src_rate.0 / ((1 << n) * m as u64);
                if actual <= target && actual > best_rate {
                    best_rate = actual;
                    best_n = n;
                    best_m = m - 1;
                }
            }
        }

        // Configure: enable, select PLL_PERIPH0(2x), set dividers
        let reg_val = (1 << 31)       // Enable
                    | (1 << 24)       // Source: PLL_PERIPH0(2x)
                    | (best_n << 8)   // N divider
                    | best_m; // M divider

        self.write_reg(clk_reg, reg_val);

        Ok(ClockRate(best_rate))
    }
}

impl ClockDriver for AllwinnerCcu {
    fn enable(&mut self, clock: ClockId) -> DriverResult<()> {
        // Map clock ID to gate register and bit
        let (gate_reg, bit) = match clock.0 {
            // UART clocks (gate2)
            0..=5 => (aw_ccu_regs::BUS_CLK_GATE2, clock.0 + 16),
            // MMC clocks (gate0)
            128..=130 => (aw_ccu_regs::BUS_CLK_GATE0, clock.0 - 128 + 8),
            // I2C clocks (gate2)
            160..=164 => (aw_ccu_regs::BUS_CLK_GATE2, clock.0 - 160),
            _ => return Err(DriverError::NotSupported),
        };

        self.enable_bus_gate(gate_reg, bit);
        Ok(())
    }

    fn disable(&mut self, clock: ClockId) -> DriverResult<()> {
        let (gate_reg, bit) = match clock.0 {
            0..=5 => (aw_ccu_regs::BUS_CLK_GATE2, clock.0 + 16),
            128..=130 => (aw_ccu_regs::BUS_CLK_GATE0, clock.0 - 128 + 8),
            160..=164 => (aw_ccu_regs::BUS_CLK_GATE2, clock.0 - 160),
            _ => return Err(DriverError::NotSupported),
        };

        self.disable_bus_gate(gate_reg, bit);
        Ok(())
    }

    fn is_enabled(&self, clock: ClockId) -> DriverResult<bool> {
        let (gate_reg, bit) = match clock.0 {
            0..=5 => (aw_ccu_regs::BUS_CLK_GATE2, clock.0 + 16),
            128..=130 => (aw_ccu_regs::BUS_CLK_GATE0, clock.0 - 128 + 8),
            160..=164 => (aw_ccu_regs::BUS_CLK_GATE2, clock.0 - 160),
            _ => return Err(DriverError::NotSupported),
        };

        let val = self.read_reg(gate_reg);
        Ok((val & (1 << bit)) != 0)
    }

    fn get_rate(&self, clock: ClockId) -> DriverResult<ClockRate> {
        match clock.0 {
            // CPU PLL
            0 => Ok(self.get_cpu_pll_rate()),
            // PERIPH0 PLL
            4 => Ok(self.get_periph0_pll_rate()),
            // APB1 (typically PERIPH0 / 4)
            35 => Ok(ClockRate(self.get_periph0_pll_rate().0 / 4)),
            // Others: return a default for now
            _ => Ok(self.hosc_rate),
        }
    }

    fn set_rate(&mut self, clock: ClockId, rate: ClockRate) -> DriverResult<ClockRate> {
        match clock.0 {
            // MMC clocks
            128..=130 => self.configure_mmc_clock(clock.0 - 128, rate),
            _ => Err(DriverError::NotSupported),
        }
    }

    fn get_parent(&self, _clock: ClockId) -> DriverResult<Option<ClockId>> {
        // Simplified: most clocks derive from PERIPH0 or CPU PLL
        Ok(Some(ClockId(4))) // PLL_PERIPH0
    }

    fn set_parent(&mut self, _clock: ClockId, _parent: ClockId) -> DriverResult<()> {
        // Would need clock mux configuration
        Err(DriverError::NotSupported)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clock_rate_conversions() {
        assert_eq!(ClockRate::mhz(24).as_hz(), 24_000_000);
        assert_eq!(ClockRate::khz(400).as_hz(), 400_000);
    }
}

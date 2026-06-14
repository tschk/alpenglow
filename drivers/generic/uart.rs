// Copyright 2024 Soliloquy Authors
// SPDX-License-Identifier: MPL-2.0
//
// Generic UART Driver
// Platform-agnostic UART implementation

use crate::traits::{DriverError, DriverResult, UartConfig, UartDriver, UartParity};

/// UART register offsets (16550-compatible layout)
/// Most ARM SoCs use this or a derivative
pub mod regs {
    /// Receiver Buffer Register (read) / Transmitter Holding Register (write)
    pub const RBR_THR: u32 = 0x00;
    /// Interrupt Enable Register
    pub const IER: u32 = 0x04;
    /// Interrupt Identification Register (read) / FIFO Control Register (write)
    pub const IIR_FCR: u32 = 0x08;
    /// Line Control Register
    pub const LCR: u32 = 0x0C;
    /// Modem Control Register
    pub const MCR: u32 = 0x10;
    /// Line Status Register
    pub const LSR: u32 = 0x14;
    /// Modem Status Register
    pub const MSR: u32 = 0x18;
    /// Divisor Latch Low (when DLAB=1)
    pub const DLL: u32 = 0x00;
    /// Divisor Latch High (when DLAB=1)
    pub const DLH: u32 = 0x04;
}

/// Line Status Register bits
pub mod lsr {
    pub const DATA_READY: u32 = 1 << 0;
    pub const OVERRUN_ERROR: u32 = 1 << 1;
    pub const PARITY_ERROR: u32 = 1 << 2;
    pub const FRAMING_ERROR: u32 = 1 << 3;
    pub const BREAK_INTERRUPT: u32 = 1 << 4;
    pub const TX_HOLDING_EMPTY: u32 = 1 << 5;
    pub const TX_EMPTY: u32 = 1 << 6;
    pub const FIFO_ERROR: u32 = 1 << 7;
}

/// Line Control Register bits
pub mod lcr {
    pub const WORD_LENGTH_5: u32 = 0b00;
    pub const WORD_LENGTH_6: u32 = 0b01;
    pub const WORD_LENGTH_7: u32 = 0b10;
    pub const WORD_LENGTH_8: u32 = 0b11;
    pub const STOP_BITS_1: u32 = 0 << 2;
    pub const STOP_BITS_2: u32 = 1 << 2;
    pub const PARITY_ENABLE: u32 = 1 << 3;
    pub const PARITY_EVEN: u32 = 1 << 4;
    pub const PARITY_STICK: u32 = 1 << 5;
    pub const BREAK_CONTROL: u32 = 1 << 6;
    pub const DLAB: u32 = 1 << 7;
}

/// FIFO Control Register bits
pub mod fcr {
    pub const FIFO_ENABLE: u32 = 1 << 0;
    pub const RX_FIFO_RESET: u32 = 1 << 1;
    pub const TX_FIFO_RESET: u32 = 1 << 2;
    pub const DMA_MODE: u32 = 1 << 3;
    pub const RX_TRIGGER_1: u32 = 0b00 << 6;
    pub const RX_TRIGGER_4: u32 = 0b01 << 6;
    pub const RX_TRIGGER_8: u32 = 0b10 << 6;
    pub const RX_TRIGGER_14: u32 = 0b11 << 6;
}

/// Modem Control Register bits
pub mod mcr {
    pub const DTR: u32 = 1 << 0;
    pub const RTS: u32 = 1 << 1;
    pub const OUT1: u32 = 1 << 2;
    pub const OUT2: u32 = 1 << 3;
    pub const LOOPBACK: u32 = 1 << 4;
    pub const AUTOFLOW: u32 = 1 << 5;
}

/// Generic 16550-compatible UART driver
pub struct GenericUart {
    base: *mut u32,
    clock_hz: u32,
    reg_shift: u32,
}

impl GenericUart {
    /// Create a new UART driver
    ///
    /// # Safety
    /// The caller must ensure `base` points to valid UART registers
    ///
    /// # Arguments
    /// * `base` - Base address of UART registers
    /// * `clock_hz` - Input clock frequency in Hz
    /// * `reg_shift` - Register address shift (usually 0 or 2)
    pub unsafe fn new(base: usize, clock_hz: u32, reg_shift: u32) -> Self {
        Self {
            base: base as *mut u32,
            clock_hz,
            reg_shift,
        }
    }

    #[inline]
    fn read_reg(&self, offset: u32) -> u32 {
        let reg_offset = (offset << self.reg_shift) / 4;
        unsafe { core::ptr::read_volatile(self.base.add(reg_offset as usize)) }
    }

    #[inline]
    fn write_reg(&self, offset: u32, value: u32) {
        let reg_offset = (offset << self.reg_shift) / 4;
        unsafe { core::ptr::write_volatile(self.base.add(reg_offset as usize), value) }
    }

    /// Calculate divisor for baud rate
    fn calc_divisor(&self, baud: u32) -> u16 {
        // Divisor = clock / (16 * baud)
        let divisor = (self.clock_hz + 8 * baud) / (16 * baud);
        divisor.min(0xFFFF) as u16
    }

    /// Set the baud rate divisor
    fn set_divisor(&mut self, divisor: u16) {
        // Enable DLAB to access divisor registers
        let lcr = self.read_reg(regs::LCR);
        self.write_reg(regs::LCR, lcr | lcr::DLAB);

        // Write divisor
        self.write_reg(regs::DLL, (divisor & 0xFF) as u32);
        self.write_reg(regs::DLH, ((divisor >> 8) & 0xFF) as u32);

        // Disable DLAB
        self.write_reg(regs::LCR, lcr);
    }

    /// Initialize UART with default settings (115200 8N1)
    pub fn init_default(&mut self) {
        self.configure(&UartConfig::default()).ok();
    }

    /// Check if transmit buffer is empty
    #[inline]
    pub fn tx_ready(&self) -> bool {
        (self.read_reg(regs::LSR) & lsr::TX_HOLDING_EMPTY) != 0
    }

    /// Check if receive data is available
    #[inline]
    pub fn rx_ready(&self) -> bool {
        (self.read_reg(regs::LSR) & lsr::DATA_READY) != 0
    }

    /// Write a single byte (blocking)
    pub fn write_byte(&mut self, byte: u8) {
        // Wait for TX ready
        while !self.tx_ready() {}
        self.write_reg(regs::RBR_THR, byte as u32);
    }

    /// Read a single byte (blocking)
    pub fn read_byte(&mut self) -> u8 {
        // Wait for RX ready
        while !self.rx_ready() {}
        self.read_reg(regs::RBR_THR) as u8
    }

    /// Try to read a byte (non-blocking)
    pub fn try_read_byte(&mut self) -> Option<u8> {
        if self.rx_ready() {
            Some(self.read_reg(regs::RBR_THR) as u8)
        } else {
            None
        }
    }
}

impl UartDriver for GenericUart {
    fn configure(&mut self, config: &UartConfig) -> DriverResult<()> {
        // Disable interrupts
        self.write_reg(regs::IER, 0);

        // Set baud rate
        let divisor = self.calc_divisor(config.baud_rate);
        self.set_divisor(divisor);

        // Configure line control
        let mut lcr = 0u32;

        // Data bits
        lcr |= match config.data_bits {
            5 => lcr::WORD_LENGTH_5,
            6 => lcr::WORD_LENGTH_6,
            7 => lcr::WORD_LENGTH_7,
            8 => lcr::WORD_LENGTH_8,
            _ => return Err(DriverError::InvalidParam),
        };

        // Stop bits
        lcr |= match config.stop_bits {
            1 => lcr::STOP_BITS_1,
            2 => lcr::STOP_BITS_2,
            _ => return Err(DriverError::InvalidParam),
        };

        // Parity
        lcr |= match config.parity {
            UartParity::None => 0,
            UartParity::Even => lcr::PARITY_ENABLE | lcr::PARITY_EVEN,
            UartParity::Odd => lcr::PARITY_ENABLE,
        };

        self.write_reg(regs::LCR, lcr);

        // Enable and reset FIFOs
        self.write_reg(
            regs::IIR_FCR,
            fcr::FIFO_ENABLE | fcr::RX_FIFO_RESET | fcr::TX_FIFO_RESET | fcr::RX_TRIGGER_8,
        );

        // Set MCR (flow control if enabled)
        let mcr = if config.flow_control {
            mcr::DTR | mcr::RTS | mcr::AUTOFLOW
        } else {
            mcr::DTR | mcr::RTS
        };
        self.write_reg(regs::MCR, mcr);

        Ok(())
    }

    fn write(&mut self, data: &[u8]) -> DriverResult<usize> {
        for &byte in data {
            // Wait with timeout
            let mut timeout = 100_000;
            while !self.tx_ready() && timeout > 0 {
                timeout -= 1;
            }
            if timeout == 0 {
                return Err(DriverError::Timeout);
            }
            self.write_reg(regs::RBR_THR, byte as u32);
        }
        Ok(data.len())
    }

    fn read(&mut self, buffer: &mut [u8]) -> DriverResult<usize> {
        let mut count = 0;
        for byte in buffer.iter_mut() {
            if self.rx_ready() {
                *byte = self.read_reg(regs::RBR_THR) as u8;
                count += 1;
            } else {
                break;
            }
        }
        Ok(count)
    }

    fn available(&self) -> usize {
        if self.rx_ready() {
            1
        } else {
            0
        }
    }

    fn flush(&mut self) -> DriverResult<()> {
        // Wait for transmit to complete
        let mut timeout = 1_000_000;
        while (self.read_reg(regs::LSR) & lsr::TX_EMPTY) == 0 && timeout > 0 {
            timeout -= 1;
        }
        if timeout == 0 {
            Err(DriverError::Timeout)
        } else {
            Ok(())
        }
    }
}

// ============================================================================
// Early console support (for kernel debugging)
// ============================================================================

/// Early console writer for debug output before full UART driver is available
pub struct EarlyConsole {
    base: *mut u32,
    reg_shift: u32,
}

impl EarlyConsole {
    /// Create an early console
    ///
    /// # Safety
    /// Must be called with a valid UART base address that is already initialized
    /// by the bootloader (e.g., U-Boot)
    pub const unsafe fn new(base: usize, reg_shift: u32) -> Self {
        Self {
            base: base as *mut u32,
            reg_shift,
        }
    }

    #[inline]
    fn read_lsr(&self) -> u32 {
        let offset = (regs::LSR << self.reg_shift) / 4;
        unsafe { core::ptr::read_volatile(self.base.add(offset as usize)) }
    }

    #[inline]
    fn write_thr(&self, byte: u8) {
        let offset = (regs::RBR_THR << self.reg_shift) / 4;
        unsafe { core::ptr::write_volatile(self.base.add(offset as usize), byte as u32) }
    }

    /// Write a single character (blocking)
    pub fn putc(&self, c: u8) {
        // Wait for TX ready
        while (self.read_lsr() & lsr::TX_HOLDING_EMPTY) == 0 {}
        self.write_thr(c);
    }

    /// Write a string
    pub fn puts(&self, s: &str) {
        for c in s.bytes() {
            if c == b'\n' {
                self.putc(b'\r');
            }
            self.putc(c);
        }
    }

    /// Write a hex value
    pub fn put_hex(&self, value: u32) {
        self.puts("0x");
        for i in (0..8).rev() {
            let nibble = (value >> (i * 4)) & 0xF;
            let c = if nibble < 10 {
                b'0' + nibble as u8
            } else {
                b'a' + (nibble - 10) as u8
            };
            self.putc(c);
        }
    }
}

// Make EarlyConsole safe to share (it's write-only and stateless)
unsafe impl Send for EarlyConsole {}
unsafe impl Sync for EarlyConsole {}

/// Global early console for Allwinner A527
/// UART0 at 0x02500000, register shift 2
#[cfg(feature = "allwinner")]
pub static EARLY_CONSOLE: EarlyConsole = unsafe { EarlyConsole::new(0x02500000, 2) };

/// Print macro for early console
#[macro_export]
macro_rules! early_print {
    ($($arg:tt)*) => {{
        use core::fmt::Write;
        // Would need a Write wrapper for EarlyConsole
    }};
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_divisor_calculation() {
        // 24 MHz clock, 115200 baud
        // Divisor = 24000000 / (16 * 115200) = 13.02 ≈ 13
        let uart = unsafe { GenericUart::new(0x1000, 24_000_000, 0) };
        assert_eq!(uart.calc_divisor(115200), 13);

        // 24 MHz clock, 9600 baud
        // Divisor = 24000000 / (16 * 9600) = 156.25 ≈ 156
        assert_eq!(uart.calc_divisor(9600), 156);
    }

    #[test]
    fn test_uart_config_default() {
        let config = UartConfig::default();
        assert_eq!(config.baud_rate, 115200);
        assert_eq!(config.data_bits, 8);
        assert_eq!(config.stop_bits, 1);
        assert_eq!(config.parity, UartParity::None);
        assert!(!config.flow_control);
    }
}

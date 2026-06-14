// Copyright 2024 Alpenglow Authors
// SPDX-License-Identifier: MPL-2.0
//
// Generic Driver Traits
// Platform-agnostic driver interfaces for Alpenglow OS

// Driver traits module - no crate-level attributes here

extern crate alloc;

use alloc::boxed::Box;
use alloc::string::String;
use alloc::vec::Vec;
use core::fmt;

/// Driver result type
pub type DriverResult<T> = Result<T, DriverError>;

/// Generic driver error
#[derive(Debug, Clone)]
pub enum DriverError {
    /// Hardware not found or not responding
    NotFound,
    /// Device is busy
    Busy,
    /// Invalid parameter
    InvalidParam,
    /// Timeout waiting for operation
    Timeout,
    /// I/O error
    IoError,
    /// Not supported by this driver
    NotSupported,
    /// Out of memory
    NoMemory,
    /// Permission denied
    PermissionDenied,
    /// Device-specific error
    DeviceError(u32),
    /// Custom error message
    Custom(String),
}

impl fmt::Display for DriverError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound => write!(f, "device not found"),
            Self::Busy => write!(f, "device busy"),
            Self::InvalidParam => write!(f, "invalid parameter"),
            Self::Timeout => write!(f, "operation timeout"),
            Self::IoError => write!(f, "I/O error"),
            Self::NotSupported => write!(f, "not supported"),
            Self::NoMemory => write!(f, "out of memory"),
            Self::PermissionDenied => write!(f, "permission denied"),
            Self::DeviceError(code) => write!(f, "device error: 0x{:08x}", code),
            Self::Custom(msg) => write!(f, "{}", msg),
        }
    }
}

// ============================================================================
// GPIO Trait
// ============================================================================

/// GPIO pin direction
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpioDirection {
    Input,
    Output,
}

/// GPIO pull configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpioPull {
    None,
    Up,
    Down,
}

/// GPIO pin configuration
#[derive(Debug, Clone)]
pub struct GpioConfig {
    pub direction: GpioDirection,
    pub pull: GpioPull,
    pub initial_value: bool,
}

impl Default for GpioConfig {
    fn default() -> Self {
        Self {
            direction: GpioDirection::Input,
            pull: GpioPull::None,
            initial_value: false,
        }
    }
}

/// Generic GPIO driver trait
///
/// Note: Low-level drivers typically don't implement Send+Sync as they
/// use raw pointers for MMIO access. Higher-level wrappers can add
/// thread safety if needed.
pub trait GpioDriver {
    /// Get the number of GPIO pins available
    fn pin_count(&self) -> u32;

    /// Configure a GPIO pin
    fn configure(&mut self, pin: u32, config: &GpioConfig) -> DriverResult<()>;

    /// Read the value of a GPIO pin
    fn read(&self, pin: u32) -> DriverResult<bool>;

    /// Write a value to a GPIO pin
    fn write(&mut self, pin: u32, value: bool) -> DriverResult<()>;

    /// Toggle a GPIO pin
    fn toggle(&mut self, pin: u32) -> DriverResult<()> {
        let current = self.read(pin)?;
        self.write(pin, !current)
    }

    /// Set alternate function for a pin (if supported)
    fn set_alt_function(&mut self, pin: u32, function: u32) -> DriverResult<()>;
}

// ============================================================================
// Clock Trait
// ============================================================================

/// Clock identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClockId(pub u32);

/// Clock rate in Hz
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClockRate(pub u64);

impl ClockRate {
    pub const fn mhz(mhz: u64) -> Self {
        Self(mhz * 1_000_000)
    }

    pub const fn khz(khz: u64) -> Self {
        Self(khz * 1_000)
    }

    pub fn as_hz(&self) -> u64 {
        self.0
    }
}

/// Generic clock driver trait
pub trait ClockDriver {
    /// Enable a clock
    fn enable(&mut self, clock: ClockId) -> DriverResult<()>;

    /// Disable a clock
    fn disable(&mut self, clock: ClockId) -> DriverResult<()>;

    /// Check if a clock is enabled
    fn is_enabled(&self, clock: ClockId) -> DriverResult<bool>;

    /// Get the current rate of a clock
    fn get_rate(&self, clock: ClockId) -> DriverResult<ClockRate>;

    /// Set the rate of a clock
    fn set_rate(&mut self, clock: ClockId, rate: ClockRate) -> DriverResult<ClockRate>;

    /// Get the parent clock (if applicable)
    fn get_parent(&self, clock: ClockId) -> DriverResult<Option<ClockId>>;

    /// Set the parent clock (if applicable)
    fn set_parent(&mut self, clock: ClockId, parent: ClockId) -> DriverResult<()>;
}

// ============================================================================
// Reset Trait
// ============================================================================

/// Reset identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ResetId(pub u32);

/// Generic reset controller trait
pub trait ResetDriver {
    /// Assert a reset signal
    fn assert(&mut self, reset: ResetId) -> DriverResult<()>;

    /// Deassert a reset signal
    fn deassert(&mut self, reset: ResetId) -> DriverResult<()>;

    /// Check if a reset is asserted
    fn is_asserted(&self, reset: ResetId) -> DriverResult<bool>;

    /// Pulse a reset (assert then deassert)
    fn reset(&mut self, reset: ResetId) -> DriverResult<()> {
        self.assert(reset)?;
        // Small delay would go here in real implementation
        self.deassert(reset)
    }
}

// ============================================================================
// MMC/SD Trait
// ============================================================================

/// MMC card type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MmcCardType {
    Mmc,
    Sd,
    SdHc,
    SdXc,
    Emmc,
}

/// MMC bus width
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MmcBusWidth {
    Width1,
    Width4,
    Width8,
}

/// MMC card information
#[derive(Debug, Clone)]
pub struct MmcCardInfo {
    pub card_type: MmcCardType,
    pub capacity_bytes: u64,
    pub block_size: u32,
    pub bus_width: MmcBusWidth,
    pub max_frequency: u32,
}

/// Generic MMC/SD driver trait
pub trait MmcDriver {
    /// Initialize the MMC controller
    fn init(&mut self) -> DriverResult<()>;

    /// Detect if a card is present
    fn card_present(&self) -> bool;

    /// Get card information
    fn card_info(&self) -> DriverResult<MmcCardInfo>;

    /// Read blocks from the card
    fn read_blocks(&mut self, start_block: u64, buffer: &mut [u8]) -> DriverResult<usize>;

    /// Write blocks to the card
    fn write_blocks(&mut self, start_block: u64, data: &[u8]) -> DriverResult<usize>;

    /// Erase blocks
    fn erase_blocks(&mut self, start_block: u64, block_count: u64) -> DriverResult<()>;

    /// Flush any cached writes
    fn flush(&mut self) -> DriverResult<()>;
}

// ============================================================================
// I2C Trait
// ============================================================================

/// I2C speed mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum I2cSpeed {
    Standard, // 100 kHz
    Fast,     // 400 kHz
    FastPlus, // 1 MHz
    High,     // 3.4 MHz
}

/// Generic I2C driver trait
pub trait I2cDriver {
    /// Set the bus speed
    fn set_speed(&mut self, speed: I2cSpeed) -> DriverResult<()>;

    /// Write data to a device
    fn write(&mut self, addr: u8, data: &[u8]) -> DriverResult<()>;

    /// Read data from a device
    fn read(&mut self, addr: u8, buffer: &mut [u8]) -> DriverResult<()>;

    /// Write then read (combined transaction)
    fn write_read(
        &mut self,
        addr: u8,
        write_data: &[u8],
        read_buffer: &mut [u8],
    ) -> DriverResult<()>;

    /// Scan for devices on the bus
    fn scan(&mut self) -> DriverResult<Vec<u8>>;
}

// ============================================================================
// SPI Trait
// ============================================================================

/// SPI mode (CPOL, CPHA)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpiMode {
    Mode0, // CPOL=0, CPHA=0
    Mode1, // CPOL=0, CPHA=1
    Mode2, // CPOL=1, CPHA=0
    Mode3, // CPOL=1, CPHA=1
}

/// SPI configuration
#[derive(Debug, Clone)]
pub struct SpiConfig {
    pub mode: SpiMode,
    pub frequency: u32,
    pub bits_per_word: u8,
    pub lsb_first: bool,
}

impl Default for SpiConfig {
    fn default() -> Self {
        Self {
            mode: SpiMode::Mode0,
            frequency: 1_000_000,
            bits_per_word: 8,
            lsb_first: false,
        }
    }
}

/// Generic SPI driver trait
pub trait SpiDriver {
    /// Configure the SPI bus
    fn configure(&mut self, config: &SpiConfig) -> DriverResult<()>;

    /// Transfer data (simultaneous read/write)
    fn transfer(&mut self, tx: &[u8], rx: &mut [u8]) -> DriverResult<()>;

    /// Write data only
    fn write(&mut self, data: &[u8]) -> DriverResult<()>;

    /// Read data only
    fn read(&mut self, buffer: &mut [u8]) -> DriverResult<()>;
}

// ============================================================================
// UART Trait
// ============================================================================

/// UART parity
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UartParity {
    None,
    Even,
    Odd,
}

/// UART configuration
#[derive(Debug, Clone)]
pub struct UartConfig {
    pub baud_rate: u32,
    pub data_bits: u8,
    pub stop_bits: u8,
    pub parity: UartParity,
    pub flow_control: bool,
}

impl Default for UartConfig {
    fn default() -> Self {
        Self {
            baud_rate: 115200,
            data_bits: 8,
            stop_bits: 1,
            parity: UartParity::None,
            flow_control: false,
        }
    }
}

/// Generic UART driver trait
pub trait UartDriver {
    /// Configure the UART
    fn configure(&mut self, config: &UartConfig) -> DriverResult<()>;

    /// Write data
    fn write(&mut self, data: &[u8]) -> DriverResult<usize>;

    /// Read data (non-blocking)
    fn read(&mut self, buffer: &mut [u8]) -> DriverResult<usize>;

    /// Check if data is available to read
    fn available(&self) -> usize;

    /// Flush transmit buffer
    fn flush(&mut self) -> DriverResult<()>;
}

// ============================================================================
// PWM Trait
// ============================================================================

/// PWM configuration
#[derive(Debug, Clone)]
pub struct PwmConfig {
    pub frequency: u32,
    pub duty_cycle: f32, // 0.0 - 1.0
    pub polarity_inverted: bool,
}

/// Generic PWM driver trait
pub trait PwmDriver {
    /// Get the number of PWM channels
    fn channel_count(&self) -> u32;

    /// Configure a PWM channel
    fn configure(&mut self, channel: u32, config: &PwmConfig) -> DriverResult<()>;

    /// Enable a PWM channel
    fn enable(&mut self, channel: u32) -> DriverResult<()>;

    /// Disable a PWM channel
    fn disable(&mut self, channel: u32) -> DriverResult<()>;

    /// Set duty cycle (0.0 - 1.0)
    fn set_duty(&mut self, channel: u32, duty: f32) -> DriverResult<()>;
}

// ============================================================================
// Interrupt Trait
// ============================================================================

/// Interrupt trigger type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InterruptTrigger {
    LevelHigh,
    LevelLow,
    EdgeRising,
    EdgeFalling,
    EdgeBoth,
}

/// Interrupt handler function type
pub type InterruptHandler = Box<dyn Fn() + Send + Sync>;

/// Generic interrupt controller trait
pub trait InterruptDriver {
    /// Enable an interrupt
    fn enable(&mut self, irq: u32) -> DriverResult<()>;

    /// Disable an interrupt
    fn disable(&mut self, irq: u32) -> DriverResult<()>;

    /// Set trigger type for an interrupt
    fn set_trigger(&mut self, irq: u32, trigger: InterruptTrigger) -> DriverResult<()>;

    /// Acknowledge/clear an interrupt
    fn acknowledge(&mut self, irq: u32) -> DriverResult<()>;

    /// Check if an interrupt is pending
    fn is_pending(&self, irq: u32) -> bool;

    /// Set interrupt priority (0 = highest)
    fn set_priority(&mut self, irq: u32, priority: u8) -> DriverResult<()>;
}

// ============================================================================
// Power Management Trait
// ============================================================================

/// Power domain identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PowerDomain(pub u32);

/// Voltage regulator identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RegulatorId(pub u32);

/// Generic power management trait
pub trait PowerDriver {
    /// Enable a power domain
    fn power_on(&mut self, domain: PowerDomain) -> DriverResult<()>;

    /// Disable a power domain
    fn power_off(&mut self, domain: PowerDomain) -> DriverResult<()>;

    /// Set voltage for a regulator (in microvolts)
    fn set_voltage(&mut self, regulator: RegulatorId, voltage_uv: u32) -> DriverResult<()>;

    /// Get current voltage for a regulator (in microvolts)
    fn get_voltage(&self, regulator: RegulatorId) -> DriverResult<u32>;

    /// Enable a regulator
    fn enable_regulator(&mut self, regulator: RegulatorId) -> DriverResult<()>;

    /// Disable a regulator
    fn disable_regulator(&mut self, regulator: RegulatorId) -> DriverResult<()>;
}

// ============================================================================
// DMA Trait
// ============================================================================

/// DMA transfer direction
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DmaDirection {
    MemToMem,
    MemToDev,
    DevToMem,
}

/// DMA channel identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DmaChannel(pub u32);

/// DMA transfer descriptor
#[derive(Debug, Clone)]
pub struct DmaTransfer {
    pub src_addr: u64,
    pub dst_addr: u64,
    pub length: usize,
    pub direction: DmaDirection,
}

/// Generic DMA driver trait
pub trait DmaDriver {
    /// Allocate a DMA channel
    fn allocate_channel(&mut self) -> DriverResult<DmaChannel>;

    /// Free a DMA channel
    fn free_channel(&mut self, channel: DmaChannel) -> DriverResult<()>;

    /// Start a DMA transfer
    fn start_transfer(&mut self, channel: DmaChannel, transfer: &DmaTransfer) -> DriverResult<()>;

    /// Wait for transfer completion
    fn wait_complete(&mut self, channel: DmaChannel) -> DriverResult<()>;

    /// Check if transfer is complete
    fn is_complete(&self, channel: DmaChannel) -> bool;

    /// Abort a transfer
    fn abort(&mut self, channel: DmaChannel) -> DriverResult<()>;
}

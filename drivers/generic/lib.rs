// Copyright 2024 Alpenglow Authors
// SPDX-License-Identifier: MPL-2.0
//
// Generic Drivers Library
// Platform-agnostic hardware driver implementations for Alpenglow OS
//
// This crate provides:
// - Abstract driver traits (GPIO, Clock, MMC, UART, etc.)
// - Generic implementations that work with MMIO
// - Platform-specific implementations (Allwinner, etc.)

#![no_std]

extern crate alloc;

pub mod clock;
pub mod gpio;
pub mod mmc;
pub mod traits;
pub mod uart;

// Re-export commonly used types
pub use clock::{AllwinnerCcu, ClockDesc, ClockSource, GenericClockController};
pub use gpio::{AllwinnerGpio, GpioBank, GpioController};
pub use mmc::{BlockDevice, GenericMmcDriver, MmcHostOps};
pub use traits::*;
pub use uart::{EarlyConsole, GenericUart};

/// Driver version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Initialize early console for boot debugging
///
/// # Safety
/// Must be called with correct UART base address for the platform
#[cfg(feature = "allwinner")]
pub unsafe fn init_early_console() -> &'static EarlyConsole {
    &uart::EARLY_CONSOLE
}

/// Platform detection
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    AllwinnerA527,
    AllwinnerH616,
    AllwinnerA64,
    RockchipRK3588,
    Unknown,
}

impl Platform {
    /// Detect platform from device tree compatible string
    pub fn detect_from_compatible(compatible: &str) -> Self {
        if compatible.contains("sun55i-a527") || compatible.contains("cubie-a5e") {
            Self::AllwinnerA527
        } else if compatible.contains("sun50i-h616") {
            Self::AllwinnerH616
        } else if compatible.contains("sun50i-a64") {
            Self::AllwinnerA64
        } else if compatible.contains("rk3588") {
            Self::RockchipRK3588
        } else {
            Self::Unknown
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_platform_detection() {
        assert_eq!(
            Platform::detect_from_compatible("allwinner,sun55i-a527"),
            Platform::AllwinnerA527
        );
        assert_eq!(
            Platform::detect_from_compatible("radxa,cubie-a5e"),
            Platform::AllwinnerA527
        );
        assert_eq!(
            Platform::detect_from_compatible("unknown-soc"),
            Platform::Unknown
        );
    }
}

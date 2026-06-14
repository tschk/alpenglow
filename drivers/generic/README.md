# Generic Drivers for Soliloquy OS

Platform-agnostic hardware driver implementations that can be used across
different ARM SoCs.

## Overview

This crate provides abstract driver traits and generic implementations for
common hardware peripherals:

| Driver | Description | Platforms |
|--------|-------------|-----------|
| GPIO | General Purpose I/O | All |
| Clock | Clock/Reset Control | All |
| MMC/SD | SD Card and eMMC | All |
| UART | Serial console | All |

## Architecture

```
┌─────────────────────────────────────────────┐
│              Application Layer              │
├─────────────────────────────────────────────┤
│           Driver Traits (traits.rs)         │
│   GpioDriver, ClockDriver, MmcDriver, etc.  │
├─────────────────────────────────────────────┤
│        Generic Implementations              │
│   GpioBank, GenericMmcDriver, GenericUart   │
├─────────────────────────────────────────────┤
│       Platform-Specific Drivers             │
│   AllwinnerGpio, AllwinnerCcu, etc.         │
├─────────────────────────────────────────────┤
│              Hardware (MMIO)                │
└─────────────────────────────────────────────┘
```

## Usage

### GPIO Example

```rust
use soliloquy_drivers::{AllwinnerGpio, GpioDriver, GpioConfig, GpioDirection};

// Create GPIO controller for Allwinner A527
let mut gpio = unsafe { AllwinnerGpio::new(0x02000000, 8) };

// Configure pin as output
gpio.configure(10, &GpioConfig {
    direction: GpioDirection::Output,
    initial_value: true,
    ..Default::default()
})?;

// Toggle LED
gpio.toggle(10)?;
```

### Clock Example

```rust
use soliloquy_drivers::{AllwinnerCcu, ClockDriver, ClockId, ClockRate};

// Create CCU driver
let mut ccu = unsafe { AllwinnerCcu::new(0x02001000) };

// Enable UART0 clock
ccu.enable(ClockId(144))?;  // CLK_BUS_UART0

// Configure MMC0 clock
ccu.configure_mmc_clock(0, ClockRate::mhz(50))?;
```

### MMC Example

```rust
use soliloquy_drivers::{GenericMmcDriver, MmcDriver, BlockDevice};

// Implement MmcHostOps for your platform
struct MyMmcHost { /* ... */ }
impl MmcHostOps for MyMmcHost { /* ... */ }

let host = MyMmcHost::new();
let mut mmc = GenericMmcDriver::new(host);

// Initialize card
mmc.init()?;

// Read first sector
let mut buffer = [0u8; 512];
mmc.read_blocks(0, &mut buffer)?;
```

### UART Example

```rust
use soliloquy_drivers::{GenericUart, UartDriver, UartConfig};

// Create UART driver (24 MHz clock, register shift 2)
let mut uart = unsafe { GenericUart::new(0x02500000, 24_000_000, 2) };

// Configure for 115200 8N1
uart.configure(&UartConfig::default())?;

// Write data
uart.write(b"Hello, Soliloquy!\n")?;
```

## Traits

### `GpioDriver`

```rust
pub trait GpioDriver: Send + Sync {
    fn pin_count(&self) -> u32;
    fn configure(&mut self, pin: u32, config: &GpioConfig) -> DriverResult<()>;
    fn read(&self, pin: u32) -> DriverResult<bool>;
    fn write(&mut self, pin: u32, value: bool) -> DriverResult<()>;
    fn toggle(&mut self, pin: u32) -> DriverResult<()>;
    fn set_alt_function(&mut self, pin: u32, function: u32) -> DriverResult<()>;
}
```

### `ClockDriver`

```rust
pub trait ClockDriver: Send + Sync {
    fn enable(&mut self, clock: ClockId) -> DriverResult<()>;
    fn disable(&mut self, clock: ClockId) -> DriverResult<()>;
    fn is_enabled(&self, clock: ClockId) -> DriverResult<bool>;
    fn get_rate(&self, clock: ClockId) -> DriverResult<ClockRate>;
    fn set_rate(&mut self, clock: ClockId, rate: ClockRate) -> DriverResult<ClockRate>;
}
```

### `MmcDriver`

```rust
pub trait MmcDriver: Send + Sync {
    fn init(&mut self) -> DriverResult<()>;
    fn card_present(&self) -> bool;
    fn card_info(&self) -> DriverResult<MmcCardInfo>;
    fn read_blocks(&mut self, start: u64, buffer: &mut [u8]) -> DriverResult<usize>;
    fn write_blocks(&mut self, start: u64, data: &[u8]) -> DriverResult<usize>;
    fn erase_blocks(&mut self, start: u64, count: u64) -> DriverResult<()>;
    fn flush(&mut self) -> DriverResult<()>;
}
```

### `UartDriver`

```rust
pub trait UartDriver: Send + Sync {
    fn configure(&mut self, config: &UartConfig) -> DriverResult<()>;
    fn write(&mut self, data: &[u8]) -> DriverResult<usize>;
    fn read(&mut self, buffer: &mut [u8]) -> DriverResult<usize>;
    fn available(&self) -> usize;
    fn flush(&mut self) -> DriverResult<()>;
}
```

## Platform Support

### Allwinner A527

The Allwinner A527 (sun55i) is the primary target. Enable with:

```toml
[dependencies]
soliloquy-drivers = { features = ["allwinner"] }
```

Register base addresses:
- PIO (GPIO): 0x02000000
- CCU (Clock): 0x02001000
- R-CCU: 0x07010000
- UART0: 0x02500000
- MMC0: 0x04020000
- MMC1: 0x04021000
- MMC2: 0x04022000

## Testing

```bash
cd drivers/generic
cargo test
```

## Adding New Platforms

1. Implement the relevant traits in new files (e.g., `rockchip.rs`)
2. Add platform feature flag in `Cargo.toml`
3. Update `lib.rs` to export new implementations
4. Add to `Platform` enum for detection

## License

MPL-2.0

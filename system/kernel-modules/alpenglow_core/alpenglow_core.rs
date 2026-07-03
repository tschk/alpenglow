// SPDX-License-Identifier: GPL-2.0
#![allow(missing_docs)]
//! Alpenglow core — records boot time and appliance state.

use kernel::prelude::*;

module! {
    type: AlpenglowCore,
    name: "alpenglow_core",
    author: "Alpenglow Contributors",
    description: "Alpenglow appliance core module",
    license: "GPL",
}

struct AlpenglowCore;

impl kernel::Module for AlpenglowCore {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        let boot_ns = kernel::time::ktime_get_boot_ns();
        let boot_ms = boot_ns / 1_000_000;

        pr_info!("alpenglow: boot_time_ns={}\n", boot_ns);
        pr_info!("alpenglow: boot_time_ms={} ({}s)\n", boot_ms, boot_ms / 1000);
        pr_info!("alpenglow: ready\n");

        Ok(AlpenglowCore)
    }
}

impl Drop for AlpenglowCore {
    fn drop(&mut self) {
        pr_info!("alpenglow: unloaded\n");
    }
}

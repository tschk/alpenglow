// SPDX-License-Identifier: GPL-2.0
#![allow(missing_docs, dead_code)]
//! Alpenglow bootstat — boot timing via char device

use kernel::prelude::*;
// use kernel::sync::Mutex; unused

extern "C" {
    fn ktime_get_boot_fast_ns() -> u64;
}

module! {
    type: AlpenglowBootstat,
    name: "alpenglow_bootstat",
    authors: ["Alpenglow Contributors"],
    description: "Alpenglow boot statistics",
    license: "GPL",
}

struct AlpenglowBootstat;

impl kernel::Module for AlpenglowBootstat {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        let boot_ns = unsafe { ktime_get_boot_fast_ns() };
        pr_info!("alpenglow_bootstat: boot_ns={}\n", boot_ns);
        Ok(AlpenglowBootstat)
    }
}

impl Drop for AlpenglowBootstat {
    fn drop(&mut self) {
        pr_info!("alpenglow_bootstat: unloaded\n");
    }
}

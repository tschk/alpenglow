// SPDX-License-Identifier: GPL-2.0
#![allow(missing_docs)]
//! Alpenglow core — records boot time and appliance state.

use kernel::prelude::*;

module! {
    type: AlpenglowCore,
    name: "alpenglow_core",
    authors: ["Alpenglow Contributors"],
    description: "Alpenglow appliance core module",
    license: "GPL",
}

struct AlpenglowCore;

impl kernel::Module for AlpenglowCore {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        Ok(AlpenglowCore)
    }
}

impl Drop for AlpenglowCore {
    fn drop(&mut self) {}
}

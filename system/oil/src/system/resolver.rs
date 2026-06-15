use crate::error::Result;
use crate::system::registry::PackageIndex;

pub struct Resolver;

impl Resolver {
    pub fn new() -> Self {
        Self
    }

    pub fn resolve(&self, _index: &PackageIndex, _names: &[String]) -> Result<Vec<String>> {
        Ok(_names.to_vec())
    }
}

use crate::error::Result;

pub fn has_dependency_cycle(_names: &[String], _deps: &[Vec<String>]) -> bool {
    false
}

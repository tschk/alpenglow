//! Qualified package names: `brew/openssl` (force Linuxbrew) or plain `ripgrep` for auto.

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub enum Ecosystem {
    /// Local Homebrew-style index (fastest: cached JSON).
    Brew,
}

impl Ecosystem {
    /// Lower is faster / preferred when the same logical package exists in multiple ecosystems.
    pub fn speed_rank(self) -> u8 {
        match self {
            Ecosystem::Brew => 0,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Ecosystem::Brew => "brew",
        }
    }
}

#[derive(Debug, Clone)]
pub struct PackageSpec {
    /// When set, install/search only this ecosystem.
    pub force: Option<Ecosystem>,
    /// Unqualified package id (no bang prefix).
    pub name: String,
}

/// Parse `brew/foo`, `homebrew/foo`.
pub fn parse_package_spec(raw: &str) -> PackageSpec {
    let lower = raw.to_lowercase();
    const PAIRS: &[(&str, Ecosystem)] = &[
        ("brew/", Ecosystem::Brew),
        ("homebrew/", Ecosystem::Brew),
    ];
    for (prefix, eco) in PAIRS {
        if lower.starts_with(prefix) {
            return PackageSpec {
                force: Some(*eco),
                name: raw[prefix.len()..].to_string(),
            };
        }
    }
    PackageSpec {
        force: None,
        name: raw.to_string(),
    }
}

/// Strip a search query bang for remote search (same rules as install).
pub fn parse_search_query(raw: &str) -> (Option<Ecosystem>, String) {
    let spec = parse_package_spec(raw);
    (spec.force, spec.name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_bangs_case_insensitive_prefix() {
        let s = parse_package_spec("Brew/RipGrep");
        assert_eq!(s.force, Some(Ecosystem::Brew));
        assert_eq!(s.name, "RipGrep");
    }

    #[test]
    fn plain_name_is_auto() {
        let s = parse_package_spec("ripgrep");
        assert!(s.force.is_none());
        assert_eq!(s.name, "ripgrep");
    }

    #[test]
    fn parse_search_query_strips_known_prefixes() {
        let (f, q) = parse_search_query("brew/openssl");
        assert_eq!(f, Some(Ecosystem::Brew));
        assert_eq!(q, "openssl");
    }

    #[test]
    fn speed_rank_orders_fastest_first() {
        assert_eq!(Ecosystem::Brew.speed_rank(), 0);
    }
}

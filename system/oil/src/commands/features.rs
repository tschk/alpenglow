use crate::error::Result;
use console::style;

/// Experimental feature flags. Gate new capabilities here before they graduate
/// to stable. Each flag can be enabled via the `WAX_FEATURE_<NAME>=1` env var.
struct Feature {
    name: &'static str,
    description: &'static str,
    env_var: &'static str,
}

const FEATURES: &[Feature] = &[
    Feature {
        name: "parallel-downloads",
        description: "Download multiple packages concurrently (enabled by default)",
        env_var: "WAX_FEATURE_PARALLEL_DOWNLOADS",
    },
    Feature {
        name: "source-build-fallback",
        description: "Automatically fall back to source build when no bottle matches the host",
        env_var: "WAX_FEATURE_SOURCE_BUILD_FALLBACK",
    },
    Feature {
        name: "system-generations",
        description: "Atomic generation snapshots for OS-level package state (Linux)",
        env_var: "WAX_FEATURE_SYSTEM_GENERATIONS",
    },
];

pub fn features() -> Result<()> {
    println!();
    println!("{}", style("Feature Flags").bold());
    println!(
        "  Enable via environment variable, e.g. {}",
        style("WAX_FEATURE_REST_SOURCES=1 wax ...").dim()
    );
    println!();

    for feat in FEATURES {
        let enabled = std::env::var(feat.env_var)
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false);

        let status = if enabled {
            style("enabled ").green().to_string()
        } else {
            style("disabled").dim().to_string()
        };

        println!(
            "  [{status}]  {name}",
            status = status,
            name = style(feat.name).magenta()
        );
        println!("             {}", style(feat.description).dim());
    }

    println!();
    Ok(())
}

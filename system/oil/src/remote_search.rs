//! Aggregated remote search across Linuxbrew registries.

use crate::cache::Cache;
use crate::error::Result;
use crate::package_spec::Ecosystem;
use console::style;
use std::collections::HashMap;


/// Single result from a remote search.
#[derive(Debug, Clone)]
pub struct RemoteHit {
    pub id: String,
    pub ecosystem: Ecosystem,
    #[allow(dead_code)]
    pub version: String,
    pub description: String,
}

/// Collect remote search results from brew index.
pub async fn collect_remote_hits(
    cache: &Cache,
    q: &str,
) -> Result<Vec<RemoteHit>> {
    let mut hits = Vec::new();
    let q = q.to_lowercase();

    // Search Brew formulae
    let formulae = cache.load_all_formulae().await?;
    for formula in &formulae {
        if formula.name.to_lowercase().contains(&q)
            || formula
                .desc
                .as_deref()
                .unwrap_or("")
                .to_lowercase()
                .contains(&q)
        {
            hits.push(RemoteHit {
                id: formula.name.clone(),
                ecosystem: Ecosystem::Brew,
                version: formula.versions.stable.clone(),
                description: formula.desc.clone().unwrap_or_default(),
            });
        }
    }

    dedupe_hits(&mut hits);
    hits.sort_by(|a, b| {
        let a_score = score::score_hit(a, &q);
        let b_score = score::score_hit(b, &q);
        b_score.cmp(&a_score).then_with(|| a.id.cmp(&b.id))
    });

    Ok(hits)
}

fn dedupe_hits(hits: &mut Vec<RemoteHit>) {
    let mut seen: HashMap<String, RemoteHit> = HashMap::new();
    for hit in hits.drain(..) {
        let key = hit.id.to_lowercase();
        match seen.get(&key) {
            Some(existing) => {
                // Prefer higher-scored, same-ecosystem entries keep higher score
                if hit.ecosystem == existing.ecosystem {
                    let existing_score = score::score_hit(existing, &key);
                    let hit_score = score::score_hit(&hit, &key);
                    if hit_score > existing_score {
                        seen.insert(key, hit);
                    }
                } else if hit.ecosystem.speed_rank() < existing.ecosystem.speed_rank() {
                    seen.insert(key, hit);
                }
            }
            None => {
                seen.insert(key, hit);
            }
        }
    }
    hits.extend(seen.into_values());
}

/// Format a single search result line.
pub fn format_remote_hit(hit: &RemoteHit) -> String {
    let eco_tag = match hit.ecosystem {
        Ecosystem::Brew => style("brew").cyan(),
    };
    let desc = if hit.description.is_empty() {
        String::new()
    } else {
        format!(" {}", style(&hit.description).dim())
    };
    format!(
        "{} {} {}",
        eco_tag,
        style(&hit.id).magenta(),
        desc
    )
}

pub fn format_remote_result(hits: &[RemoteHit]) -> String {
    if hits.is_empty() {
        return "no remote results".to_string();
    }
    format!(
        "→ {} result{}",
        hits.len(),
        if hits.len() == 1 { "" } else { "s" }
    )
}

mod score {
    use super::RemoteHit;

    pub fn score_hit(hit: &RemoteHit, q: &str) -> usize {
        let id_lower = hit.id.to_lowercase();
        let desc_lower = hit.description.to_lowercase();
        let mut score = 0;

        // Exact match
        if id_lower == q {
            score += 100;
        }
        // Starts with
        if id_lower.starts_with(q) {
            score += 50;
        }
        // Contains in name
        if id_lower.contains(q) {
            score += 10;
        }
        // Contains in description
        if desc_lower.contains(q) {
            score += 3;
        }
        score
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dedupe_case_folds_ids() {
        let mut hits = vec![
            RemoteHit {
                id: "Hello".into(),
                ecosystem: Ecosystem::Brew,
                version: "1.0".into(),
                description: "".into(),
            },
            RemoteHit {
                id: "hello".into(),
                ecosystem: Ecosystem::Brew,
                version: "1.0".into(),
                description: "".into(),
            },
        ];
        dedupe_hits(&mut hits);
        assert_eq!(hits.len(), 1);
    }

    #[test]
    fn dedupe_same_ecosystem_keeps_higher_score() {
        let mut hits = vec![
            RemoteHit {
                id: "hello".into(),
                ecosystem: Ecosystem::Brew,
                version: "1.0".into(),
                description: "something".into(),
            },
            RemoteHit {
                id: "hello".into(),
                ecosystem: Ecosystem::Brew,
                version: "2.0".into(),
                description: "".into(),
            },
        ];
        dedupe_hits(&mut hits);
        assert_eq!(hits.len(), 1);
        // Higher-scored (more description) should be kept
        assert_eq!(hits[0].description, "something");
    }
}

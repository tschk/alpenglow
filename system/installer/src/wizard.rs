//! Installer wizard logic that does not depend on the GUI toolkit.
//!
//! The flow follows Calamares' pages, trimmed to what an image-based installer can really do:
//! requirements (welcome) -> disk (partition) -> summary -> install (exec, with progress) ->
//! finished. Locale, keyboard and user pages are intentionally absent: the image is written
//! as-is, so there is nothing for them to configure.

use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Step {
    Welcome,
    Disk,
    Review,
    Install,
    Finish,
}

impl Step {
    pub const ALL: [Step; 5] = [
        Step::Welcome,
        Step::Disk,
        Step::Review,
        Step::Install,
        Step::Finish,
    ];

    pub fn index(self) -> usize {
        Self::ALL
            .iter()
            .position(|step| *step == self)
            .unwrap_or_default()
    }

    /// Sidebar label.
    pub fn title(self) -> &'static str {
        match self {
            Step::Welcome => "Welcome",
            Step::Disk => "Disk",
            Step::Review => "Summary",
            Step::Install => "Install",
            Step::Finish => "Finish",
        }
    }

    pub fn next(self) -> Option<Step> {
        Self::ALL.get(self.index() + 1).copied()
    }

    pub fn back(self) -> Option<Step> {
        self.index()
            .checked_sub(1)
            .and_then(|index| Self::ALL.get(index))
            .copied()
    }

    /// Back and Quit are hidden while the image is being written (a half-written disk is
    /// worse than waiting), as Calamares does during its exec phase.
    pub fn is_busy(self) -> bool {
        self == Step::Install
    }
}

/// What the user has provided so far; drives whether Continue is enabled.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Readiness {
    pub image_ok: bool,
    pub has_target: bool,
    pub confirmed: bool,
}

pub fn can_continue(step: Step, ready: Readiness) -> bool {
    match step {
        Step::Welcome => ready.image_ok,
        Step::Disk => ready.has_target,
        Step::Review => ready.has_target && ready.confirmed,
        Step::Install | Step::Finish => false,
    }
}

/// Size of the installer image, or why it cannot be used.
pub fn check_image(source: &Path) -> Result<u64, String> {
    let metadata = fs::metadata(source).map_err(|err| format!("{err}"))?;
    if !metadata.is_file() {
        return Err("not a regular file".to_string());
    }
    if metadata.len() == 0 {
        return Err("the image is empty".to_string());
    }
    Ok(metadata.len())
}

/// Whether this process can open block devices for writing (effective uid 0).
pub fn is_root() -> bool {
    fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|status| {
            status
                .lines()
                .find_map(|line| line.strip_prefix("Uid:"))
                .and_then(|ids| ids.split_whitespace().nth(1).map(str::to_owned))
        })
        .is_some_and(|euid| euid == "0")
}

/// Disks shown at once; the toolkit's templates cannot scroll, so longer lists are paged.
pub const DISKS_PER_PAGE: usize = 4;

pub fn page_count(len: usize) -> usize {
    len.div_ceil(DISKS_PER_PAGE).max(1)
}

/// Index range of the disks on `page` (clamped to the last page).
pub fn page_range(len: usize, page: usize) -> std::ops::Range<usize> {
    let page = page.min(page_count(len) - 1);
    let start = page * DISKS_PER_PAGE;
    start..(start + DISKS_PER_PAGE).min(len)
}

pub fn human_size(bytes: u64) -> String {
    let gib = bytes as f64 / 1024.0 / 1024.0 / 1024.0;
    if gib >= 1.0 {
        format!("{gib:.1} GiB")
    } else {
        let mib = bytes as f64 / 1024.0 / 1024.0;
        format!("{mib:.0} MiB")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn steps_walk_forward_and_back() {
        assert_eq!(Step::Welcome.back(), None);
        assert_eq!(Step::Welcome.next(), Some(Step::Disk));
        assert_eq!(Step::Review.next(), Some(Step::Install));
        assert_eq!(Step::Install.back(), Some(Step::Review));
        assert_eq!(Step::Finish.next(), None);
        for (index, step) in Step::ALL.iter().enumerate() {
            assert_eq!(step.index(), index);
            assert!(!step.title().is_empty());
        }
    }

    #[test]
    fn only_install_is_busy() {
        let busy: Vec<_> = Step::ALL.iter().filter(|step| step.is_busy()).collect();
        assert_eq!(busy, [&Step::Install]);
    }

    #[test]
    fn continue_requires_what_the_page_needs() {
        let none = Readiness::default();
        assert!(!can_continue(Step::Welcome, none));
        assert!(can_continue(
            Step::Welcome,
            Readiness {
                image_ok: true,
                ..none
            }
        ));
        assert!(!can_continue(Step::Disk, none));
        assert!(can_continue(
            Step::Disk,
            Readiness {
                has_target: true,
                ..none
            }
        ));
        // Writing the image needs both a target and the explicit erase confirmation.
        let target_only = Readiness {
            image_ok: true,
            has_target: true,
            confirmed: false,
        };
        assert!(!can_continue(Step::Review, target_only));
        assert!(can_continue(
            Step::Review,
            Readiness {
                confirmed: true,
                ..target_only
            }
        ));
        let all = Readiness {
            image_ok: true,
            has_target: true,
            confirmed: true,
        };
        assert!(!can_continue(Step::Install, all));
        assert!(!can_continue(Step::Finish, all));
    }

    #[test]
    fn check_image_rejects_missing_empty_and_directories() {
        let dir = tempdir().unwrap();
        assert!(check_image(&dir.path().join("missing.img")).is_err());
        assert!(check_image(dir.path()).is_err());
        let empty = dir.path().join("empty.img");
        fs::write(&empty, []).unwrap();
        assert!(check_image(&empty).is_err());
        let image = dir.path().join("ok.img");
        fs::write(&image, b"alpenglow").unwrap();
        assert_eq!(check_image(&image), Ok(9));
    }

    #[test]
    fn human_size_matches_installer_disk_labels() {
        assert_eq!(human_size(0), "0 MiB");
        assert_eq!(human_size(1024 * 1024), "1 MiB");
        assert_eq!(human_size(1024 * 1024 * 1024), "1.0 GiB");
        assert_eq!(human_size(3 * 512 * 1024 * 1024), "1.5 GiB");
    }

    #[test]
    fn paging_covers_every_disk_exactly_once() {
        assert_eq!(page_count(0), 1);
        assert_eq!(page_count(4), 1);
        assert_eq!(page_count(5), 2);
        assert_eq!(page_range(0, 0), 0..0);
        assert_eq!(page_range(3, 0), 0..3);
        assert_eq!(page_range(8, 0), 0..4);
        assert_eq!(page_range(8, 1), 4..8);
        assert_eq!(page_range(9, 2), 8..9);
        // A page past the end (e.g. after the list shrinks) shows the last page.
        assert_eq!(page_range(5, 9), 4..5);
        for len in 0..30 {
            let mut seen = Vec::new();
            for page in 0..page_count(len) {
                seen.extend(page_range(len, page));
            }
            assert_eq!(seen, (0..len).collect::<Vec<_>>());
        }
    }

    #[test]
    fn root_check_reads_proc_without_panicking() {
        // The value depends on who runs the tests; it must just be answerable.
        let _ = is_root();
    }
}

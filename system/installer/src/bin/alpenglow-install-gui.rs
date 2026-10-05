fn format_disk_size(sectors: u64) -> String {
    alpenglow_installer::wizard::human_size(sectors.saturating_mul(512))
}

fn is_install_disk_name(name: &str) -> bool {
    (name.starts_with("sd")
        || name.starts_with("vd")
        || name.starts_with("xvd")
        || name.starts_with("nvme")
        || name.starts_with("mmcblk"))
        && !name.contains("loop")
        && !name.contains("ram")
        && !name.contains("zram")
}

#[cfg(feature = "gui")]
fn main() {
    use alpenglow_installer::wizard::{
        can_continue, check_image, human_size, is_root, page_count, page_range, Readiness, Step,
    };
    use alpenglow_installer::{install_image_with_progress, parse_install_args, InstallProgress};
    use crepuscularity_gpui::prelude::*;
    use crepuscularity_gpui::{application, bounds, point, size, App, ClickEvent};
    use std::fs;
    use std::path::PathBuf;
    use std::sync::{Arc, Mutex};
    use std::time::{Duration, Instant};

    // Calamares-style pages (welcome, disk, summary, install, finished) in a macOS-Installer
    // look: step sidebar, system-blue Continue, rounded white cards.
    struct InstallerView {
        step: Step,
        source: PathBuf,
        image: Result<u64, String>,
        is_root: bool,
        forced_target: Option<PathBuf>,
        disks: Vec<DiskChoice>,
        disk_page: usize,
        target: Option<PathBuf>,
        confirmed: bool,
        status: String,
        run: Arc<Mutex<InstallRun>>,
        progress: Option<InstallProgress>,
        started: Option<Instant>,
        outcome: Option<Result<u64, String>>,
    }

    #[derive(Clone)]
    struct DiskChoice {
        path: PathBuf,
        name: String,
        title: String,
        size: String,
    }

    #[derive(Default)]
    struct InstallRun {
        progress: Option<InstallProgress>,
        outcome: Option<Result<u64, String>>,
    }

    struct SidebarItem {
        label: String,
        number: String,
        current: bool,
        done: bool,
    }

    struct Requirement {
        label: String,
        detail: String,
        ok: bool,
        warn: bool,
    }

    struct DiskCard {
        index: usize,
        title: String,
        detail: String,
        selected: bool,
    }

    impl InstallerView {
        fn new(source: PathBuf, target: Option<PathBuf>) -> Self {
            let image = check_image(&source);
            let mut view = Self {
                step: Step::Welcome,
                source,
                image,
                is_root: is_root(),
                forced_target: target.clone(),
                disks: Vec::new(),
                disk_page: 0,
                target,
                confirmed: false,
                status: String::new(),
                run: Arc::new(Mutex::new(InstallRun::default())),
                progress: None,
                started: None,
                outcome: None,
            };
            view.disks = view.list_disks();
            view
        }

        /// The disk named on the command line (if any) first, then what /sys/block reports.
        fn list_disks(&self) -> Vec<DiskChoice> {
            let mut disks = discover_disks();
            if let Some(path) = &self.forced_target {
                if !disks.iter().any(|disk| &disk.path == path) {
                    disks.insert(
                        0,
                        DiskChoice {
                            path: path.clone(),
                            name: path.display().to_string(),
                            title: "Selected target".to_string(),
                            size: "given on the command line".to_string(),
                        },
                    );
                }
            }
            disks
        }

        fn readiness(&self) -> Readiness {
            Readiness {
                image_ok: self.image.is_ok(),
                has_target: self.target.is_some(),
                confirmed: self.confirmed,
            }
        }

        fn target_disk(&self) -> Option<&DiskChoice> {
            let target = self.target.as_ref()?;
            self.disks.iter().find(|disk| &disk.path == target)
        }

        fn goto(&mut self, step: Step, cx: &mut gpui::Context<Self>) {
            self.step = step;
            self.status.clear();
            cx.notify();
        }

        fn quit(&mut self, _: &ClickEvent, _: &mut gpui::Window, cx: &mut gpui::Context<Self>) {
            cx.quit();
        }

        fn go_back(&mut self, _: &ClickEvent, _: &mut gpui::Window, cx: &mut gpui::Context<Self>) {
            if self.step.is_busy() {
                return;
            }
            if let Some(previous) = self.step.back() {
                self.confirmed = false;
                self.goto(previous, cx);
            }
        }

        fn primary(&mut self, _: &ClickEvent, _: &mut gpui::Window, cx: &mut gpui::Context<Self>) {
            if self.step != Step::Finish && !can_continue(self.step, self.readiness()) {
                return;
            }
            match self.step {
                Step::Welcome | Step::Disk => {
                    if let Some(next) = self.step.next() {
                        self.goto(next, cx);
                    }
                }
                Step::Review => self.start_install(cx),
                Step::Finish => self.restart(cx),
                Step::Install => {}
            }
        }

        fn refresh_disks(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.disks = self.list_disks();
            self.disk_page = self.disk_page.min(page_count(self.disks.len()) - 1);
            if let Some(target) = &self.target {
                if !self.disks.iter().any(|disk| &disk.path == target) {
                    self.target = None;
                }
            }
            cx.notify();
        }

        fn prev_page(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.disk_page = self.disk_page.saturating_sub(1);
            cx.notify();
        }

        fn next_page(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.disk_page = (self.disk_page + 1).min(page_count(self.disks.len()) - 1);
            cx.notify();
        }

        fn select_disk(&mut self, index: usize, cx: &mut gpui::Context<Self>) {
            let Some(disk) = self.disks.get(index) else {
                self.status = "That disk is no longer available.".to_string();
                cx.notify();
                return;
            };
            self.target = Some(disk.path.clone());
            self.status.clear();
            cx.notify();
        }

        fn toggle_confirm(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.confirmed = !self.confirmed;
            cx.notify();
        }

        fn start_install(&mut self, cx: &mut gpui::Context<Self>) {
            let Some(target) = self.target.clone() else {
                self.status = "Choose a disk first.".to_string();
                cx.notify();
                return;
            };
            self.run = Arc::new(Mutex::new(InstallRun::default()));
            self.progress = None;
            self.outcome = None;
            self.started = Some(Instant::now());
            self.status.clear();
            self.step = Step::Install;
            let run = Arc::clone(&self.run);
            let source = self.source.clone();
            std::thread::spawn(move || {
                let report = |progress: InstallProgress| {
                    if let Ok(mut run) = run.lock() {
                        run.progress = Some(progress);
                    }
                };
                let outcome = install_image_with_progress(&source, &target, false, report)
                    .map_err(|err| err.to_string());
                if let Ok(mut run) = run.lock() {
                    run.outcome = Some(outcome);
                }
            });
            cx.spawn(async move |this, cx| loop {
                cx.background_executor()
                    .timer(Duration::from_millis(120))
                    .await;
                match this.update(cx, |view, cx| view.poll_install(cx)) {
                    Ok(false) => {}
                    _ => break,
                }
            })
            .detach();
            cx.notify();
        }

        /// Copies progress from the writer thread; true once the install has finished.
        fn poll_install(&mut self, cx: &mut gpui::Context<Self>) -> bool {
            let (progress, outcome) = match self.run.lock() {
                Ok(run) => (run.progress, run.outcome.clone()),
                Err(_) => (
                    None,
                    Some(Err("the installer thread stopped unexpectedly".to_string())),
                ),
            };
            if progress.is_some() {
                self.progress = progress;
            }
            let finished = outcome.is_some();
            if finished {
                self.outcome = outcome;
                self.step = Step::Finish;
            }
            cx.notify();
            finished
        }

        fn restart(&mut self, cx: &mut gpui::Context<Self>) {
            if let Err(err) = std::process::Command::new("reboot").spawn() {
                self.status = format!("Could not restart: {err}. Restart the computer manually.");
                cx.notify();
            }
        }
    }

    impl gpui::Render for InstallerView {
        fn render(
            &mut self,
            _window: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) -> impl IntoElement {
            let step = self.step;
            let busy = step.is_busy();
            let sidebar: Vec<SidebarItem> = Step::ALL
                .iter()
                .map(|item| SidebarItem {
                    label: item.title().to_string(),
                    number: (item.index() + 1).to_string(),
                    current: *item == step,
                    done: item.index() < step.index(),
                })
                .collect();

            let source_name = self
                .source
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
                .unwrap_or_else(|| self.source.display().to_string());
            let image_ok = self.image.is_ok();
            let requirements = vec![
                Requirement {
                    label: "Installer image".to_string(),
                    detail: match &self.image {
                        Ok(bytes) => format!("{source_name} · {}", human_size(*bytes)),
                        Err(err) => format!("{} · {err}", self.source.display()),
                    },
                    ok: image_ok,
                    warn: false,
                },
                Requirement {
                    label: "Disks".to_string(),
                    detail: match self.disks.len() {
                        0 => {
                            "None found. Attach a disk, then refresh on the next page.".to_string()
                        }
                        1 => "1 disk available".to_string(),
                        count => format!("{count} disks available"),
                    },
                    ok: !self.disks.is_empty(),
                    warn: self.disks.is_empty(),
                },
                Requirement {
                    label: "Administrator access".to_string(),
                    detail: if self.is_root {
                        "Running as root".to_string()
                    } else {
                        "Not running as root. Writing to a disk will probably fail.".to_string()
                    },
                    ok: self.is_root,
                    warn: !self.is_root,
                },
            ];

            let pages = page_count(self.disks.len());
            let page = self.disk_page.min(pages - 1);
            let shown = page_range(self.disks.len(), page);
            let cards: Vec<DiskCard> = self
                .disks
                .iter()
                .enumerate()
                .skip(shown.start)
                .take(shown.len())
                .map(|(index, disk)| DiskCard {
                    index,
                    title: disk.title.clone(),
                    detail: format!("{} · {}", disk.name, disk.size),
                    selected: self.target.as_ref() == Some(&disk.path),
                })
                .collect();
            let has_pager = pages > 1;
            let can_prev = page > 0;
            let can_next = page + 1 < pages;
            let page_label = format!("{}–{} of {}", shown.start + 1, shown.end, self.disks.len());
            let has_cards = !cards.is_empty();

            let image_label = match &self.image {
                Ok(bytes) => format!("{source_name} ({})", human_size(*bytes)),
                Err(_) => source_name.clone(),
            };
            let (target_label, target_path) = self
                .target_disk()
                .map(|disk| {
                    (
                        format!("{} ({})", disk.title, disk.size),
                        disk.path.display().to_string(),
                    )
                })
                .or_else(|| {
                    self.target
                        .as_ref()
                        .map(|path| (path.display().to_string(), path.display().to_string()))
                })
                .unwrap_or_else(|| ("No disk selected".to_string(), String::new()));
            let confirmed = self.confirmed;

            let written = self.progress.map(|p| p.written).unwrap_or(0);
            let percent = self.progress.and_then(|p| p.percent());
            let filled_segments = percent.map(usize::from).unwrap_or(0);
            let segments: Vec<bool> = (0..100).map(|index| index < filled_segments).collect();
            let progress_title = match percent {
                Some(percent) => format!("Writing Alpenglow… {percent}%"),
                None => "Writing Alpenglow…".to_string(),
            };
            let progress_detail = {
                let mut parts = vec![match self.progress.and_then(|p| p.total) {
                    Some(total) => format!("{} of {}", human_size(written), human_size(total)),
                    None => format!("{} written", human_size(written)),
                }];
                if let Some(started) = self.started {
                    let seconds = started.elapsed().as_secs_f64();
                    if seconds >= 2.0 && written > 0 {
                        parts.push(format!(
                            "{}/s",
                            human_size((written as f64 / seconds) as u64)
                        ));
                    }
                }
                parts.join(" · ")
            };

            let (finish_ok, finish_title, finish_detail) = match &self.outcome {
                Some(Ok(bytes)) => (
                    true,
                    "Alpenglow is installed".to_string(),
                    format!(
                        "Wrote {} to {target_path}. Remove the installation media, then restart to start Alpenglow.",
                        human_size(*bytes)
                    ),
                ),
                Some(Err(err)) => (
                    false,
                    "The installation failed".to_string(),
                    format!("{err}. Nothing more was changed. You can go back and try again."),
                ),
                None => (false, String::new(), String::new()),
            };

            let status = self.status.clone();
            let has_status = !status.is_empty();
            let at_finish = step == Step::Finish;
            let show_quit = !busy && !at_finish;
            let show_back = !busy && !at_finish && step.back().is_some();
            let show_finish_quit = at_finish;
            let show_finish_back = at_finish && !finish_ok;
            let show_primary = !busy && (!at_finish || finish_ok);
            let primary_enabled = at_finish || can_continue(step, self.readiness());
            let primary_label = match step {
                Step::Review => "Install",
                Step::Finish => "Restart",
                _ => "Continue",
            };
            let hint = match step {
                Step::Welcome => "Nothing is changed until you click Install.",
                Step::Disk => "Choose where Alpenglow will be installed.",
                Step::Review => "The disk is erased as soon as you click Install.",
                Step::Install => "Keep this computer powered on and connected.",
                Step::Finish => "",
            };

            view! {r#"
                div bg-[#000000] text-[#ededed] size-full flex flex-row font-[Geist]
                    div bg-[#070707] border-r border-[#262626] w-[232px] flex flex-col px-4 py-6 gap-6
                        div flex flex-row items-center gap-3 px-2
                            div bg-[#ff79c6] rounded-[10px] w-9 h-9 flex items-center justify-center text-[#0b0b0b] text-lg font-bold
                                "▲"
                            div flex flex-col
                                div text-base font-semibold text-[#ededed]
                                    "Alpenglow"
                                div text-xs text-[#8a8a8a]
                                    "Installer"
                        div flex flex-col gap-1
                            for item in {sidebar.into_iter()}
                                div flex flex-row items-center gap-3 px-3 py-2 rounded-lg when:{item.current}="bg-[#171717]"
                                    if {item.done}
                                        div bg-[#bd93f9] text-[#0b0b0b] rounded-full w-5 h-5 flex items-center justify-center text-xs font-bold
                                            "✓"
                                    else if {item.current}
                                        div bg-[#0c0c0c] border-2 border-[#bd93f9] text-[#bd93f9] rounded-full w-5 h-5 flex items-center justify-center text-xs font-bold
                                            "{item.number}"
                                    else
                                        div border border-[#3a3a3a] text-[#6a6a6a] rounded-full w-5 h-5 flex items-center justify-center text-xs
                                            "{item.number}"
                                    if {item.current}
                                        div text-sm font-semibold text-[#ededed]
                                            "{item.label}"
                                    else
                                        div text-sm text-[#a1a1a1]
                                            "{item.label}"
                    div flex flex-col flex-1 h-full
                        div flex flex-col flex-1 px-12 py-10 gap-6 overflow-hidden
                            if {step == Step::Welcome}
                                div flex flex-col gap-6
                                    div flex flex-col gap-2
                                        div text-3xl font-semibold
                                            "Install Alpenglow"
                                        div text-base text-[#8a8a8a]
                                            "This writes Alpenglow to a disk of your choice. It takes a few minutes."
                                    div bg-[#0c0c0c] rounded-xl border border-[#262626] shadow-sm flex flex-col overflow-hidden
                                        for req in {requirements.into_iter()}
                                            div flex flex-row items-center gap-4 px-5 py-4 border-b border-[#1a1a1a]
                                                if {req.ok}
                                                    div bg-[#50fa7b] text-[#0b0b0b] rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold
                                                        "✓"
                                                else if {req.warn}
                                                    div bg-[#ffb86c] text-[#0b0b0b] rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold
                                                        "!"
                                                else
                                                    div bg-[#ff5555] text-[#0b0b0b] rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold
                                                        "✕"
                                                div flex flex-col gap-1
                                                    div text-sm font-semibold
                                                        "{req.label}"
                                                    div text-xs text-[#8a8a8a]
                                                        "{req.detail}"
                            else if {step == Step::Disk}
                                div flex flex-col gap-6
                                    div flex flex-row items-end justify-between gap-6
                                        div flex flex-col gap-2
                                            div text-3xl font-semibold
                                                "Select a disk"
                                            div text-base text-[#8a8a8a]
                                                "Alpenglow is installed on the disk you choose. Everything on it is erased."
                                        button bg-[#0c0c0c] border border-[#333333] shadow-sm rounded-md px-4 py-1 text-sm text-[#ededed] @click=refresh_disks
                                            "Refresh"
                                    if {has_cards}
                                        div flex flex-col gap-3
                                            for card in {cards.into_iter()}
                                                button bg-[#0c0c0c] rounded-xl border border-[#262626] shadow-sm px-4 py-3 flex flex-row items-center gap-4 when:{card.selected}="border-2 border-[#bd93f9]" @click={cx.listener(move |this, _: &ClickEvent, _, cx| this.select_disk(card.index, cx))}
                                                    div bg-[#1c1c1f] rounded-lg w-12 h-9 flex items-center justify-center
                                                        div bg-[#6a6a6a] rounded-full w-2 h-2
                                                    div flex flex-col gap-1 flex-1
                                                        div text-base font-semibold
                                                            "{card.title}"
                                                        div text-xs text-[#8a8a8a]
                                                            "{card.detail}"
                                                    if {card.selected}
                                                        div bg-[#bd93f9] text-[#0b0b0b] rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold
                                                            "✓"
                                            if {has_pager}
                                                div flex flex-row items-center justify-between px-1
                                                    div text-xs text-[#8a8a8a]
                                                        "{page_label}"
                                                    div flex flex-row items-center gap-2
                                                        if {can_prev}
                                                            button bg-[#0c0c0c] border border-[#333333] shadow-sm rounded-md px-3 py-1 text-xs @click=prev_page
                                                                "‹ Previous"
                                                        else
                                                            div bg-[#050505] border border-[#262626] rounded-md px-3 py-1 text-xs text-[#555555]
                                                                "‹ Previous"
                                                        if {can_next}
                                                            button bg-[#0c0c0c] border border-[#333333] shadow-sm rounded-md px-3 py-1 text-xs @click=next_page
                                                                "Next ›"
                                                        else
                                                            div bg-[#050505] border border-[#262626] rounded-md px-3 py-1 text-xs text-[#555555]
                                                                "Next ›"
                                    else
                                        div bg-[#0c0c0c] rounded-xl border border-[#262626] px-5 py-8 flex flex-col items-center gap-2
                                            div text-base font-semibold
                                                "No disks found"
                                            div text-sm text-[#8a8a8a]
                                                "Attach a disk and choose Refresh."
                            else if {step == Step::Review}
                                div flex flex-col gap-6
                                    div flex flex-col gap-2
                                        div text-3xl font-semibold
                                            "Ready to install"
                                        div text-base text-[#8a8a8a]
                                            "Review your choices. Nothing is written until you click Install."
                                    div bg-[#0c0c0c] rounded-xl border border-[#262626] shadow-sm flex flex-col overflow-hidden
                                        div flex flex-row items-center justify-between px-5 py-4 border-b border-[#1a1a1a]
                                            div text-sm text-[#8a8a8a]
                                                "Image"
                                            div text-sm font-semibold
                                                "{image_label}"
                                        div flex flex-row items-center justify-between px-5 py-4 border-b border-[#1a1a1a]
                                            div text-sm text-[#8a8a8a]
                                                "Disk"
                                            div flex flex-col items-end gap-1
                                                div text-sm font-semibold
                                                    "{target_label}"
                                                div text-xs text-[#8a8a8a]
                                                    "{target_path}"
                                        div flex flex-row items-center justify-between px-5 py-4
                                            div text-sm text-[#8a8a8a]
                                                "Action"
                                            div text-sm font-semibold
                                                "Erase the disk and install Alpenglow"
                                    div bg-[#1b150b] border border-[#4a3a1a] rounded-xl px-5 py-4 flex flex-row items-center gap-4
                                        div bg-[#ffb86c] text-[#0b0b0b] rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold
                                            "!"
                                        div text-sm text-[#ffb86c]
                                            "Everything on this disk will be permanently erased. This cannot be undone."
                                    button flex flex-row items-center gap-3 px-1 @click=toggle_confirm
                                        if {confirmed}
                                            div bg-[#bd93f9] text-[#0b0b0b] rounded-md w-5 h-5 flex items-center justify-center text-xs font-bold
                                                "✓"
                                        else
                                            div bg-[#0c0c0c] border border-[#3a3a3a] rounded-md w-5 h-5
                                        div text-sm
                                            "I understand that everything on this disk will be erased."
                            else if {step == Step::Install}
                                div flex flex-col gap-6
                                    div flex flex-col gap-2
                                        div text-3xl font-semibold
                                            "Installing Alpenglow"
                                        div text-base text-[#8a8a8a]
                                            "This takes a few minutes. Do not turn off or unplug this computer."
                                    div bg-[#0c0c0c] rounded-xl border border-[#262626] shadow-sm px-6 py-6 flex flex-col gap-4
                                        div text-base font-semibold
                                            "{progress_title}"
                                        div bg-[#1f1f1f] rounded-full h-2 w-full flex flex-row overflow-hidden
                                            for filled in {segments.into_iter()}
                                                div flex-1 h-full when:{filled}="bg-[#bd93f9]"
                                        div text-xs text-[#8a8a8a]
                                            "{progress_detail}"
                            else
                                div flex flex-col items-center gap-4 pt-10
                                    if {finish_ok}
                                        div bg-[#50fa7b] text-[#0b0b0b] rounded-full w-20 h-20 flex items-center justify-center text-4xl font-bold
                                            "✓"
                                    else
                                        div bg-[#ff5555] text-[#0b0b0b] rounded-full w-20 h-20 flex items-center justify-center text-4xl font-bold
                                            "✕"
                                    div text-3xl font-semibold
                                        "{finish_title}"
                                    div text-base text-[#8a8a8a] text-center
                                        "{finish_detail}"
                        div border-t border-[#262626] bg-[#050505] px-8 py-4 flex flex-row items-center justify-between gap-4
                            div flex flex-row items-center gap-4
                                if {show_quit}
                                    button bg-[#0c0c0c] border border-[#333333] shadow-sm rounded-md px-4 py-1 text-sm @click=quit
                                        "Quit"
                                if {has_status}
                                    div text-sm text-[#ff5555]
                                        "{status}"
                                else
                                    div text-xs text-[#6a6a6a]
                                        "{hint}"
                            div flex flex-row items-center gap-3
                                if {show_finish_back}
                                    button bg-[#0c0c0c] border border-[#333333] shadow-sm rounded-md px-4 py-1 text-sm @click=go_back
                                        "Go Back"
                                if {show_finish_quit}
                                    button bg-[#0c0c0c] border border-[#333333] shadow-sm rounded-md px-4 py-1 text-sm @click=quit
                                        "Quit"
                                if {show_back}
                                    button bg-[#0c0c0c] border border-[#333333] shadow-sm rounded-md px-4 py-1 text-sm @click=go_back
                                        "Go Back"
                                if {show_primary}
                                    if {primary_enabled}
                                        button bg-[#bd93f9] text-[#0b0b0b] rounded-md px-5 py-1 text-sm font-semibold @click=primary
                                            "{primary_label}"
                                    else
                                        div bg-[#2a2a2a] text-[#6a6a6a] rounded-md px-5 py-1 text-sm font-semibold
                                            "{primary_label}"
            "#}
        }
    }

    fn discover_disks() -> Vec<DiskChoice> {
        let entries: Vec<_> = fs::read_dir("/sys/block")
            .ok()
            .into_iter()
            .flat_map(|entries| entries.filter_map(Result::ok))
            .filter(|entry| {
                let name = entry.file_name().to_string_lossy().to_string();
                is_install_disk_name(&name) && PathBuf::from("/dev").join(&name).exists()
            })
            .collect();

        let mut disks = std::thread::scope(|s| {
            let mut handles = Vec::with_capacity(entries.len());
            for entry in entries {
                handles.push(s.spawn(move || {
                    let name = entry.file_name().to_string_lossy().to_string();
                    let path = PathBuf::from("/dev").join(&name);
                    let size = fs::read_to_string(entry.path().join("size")).ok();
                    let model = fs::read_to_string(entry.path().join("device/model"))
                        .ok()
                        .map(|value| value.trim().to_string())
                        .filter(|value| !value.is_empty());
                    let size = size
                        .and_then(|value| value.trim().parse::<u64>().ok())
                        .map(format_disk_size);
                    DiskChoice {
                        title: model.unwrap_or_else(|| "Disk".to_string()),
                        size: size.unwrap_or_else(|| "unknown size".to_string()),
                        path,
                        name,
                    }
                }));
            }
            handles
                .into_iter()
                .filter_map(|h| h.join().ok())
                .collect::<Vec<_>>()
        });

        disks.sort_by(|left, right| left.name.cmp(&right.name));
        disks
    }

    let (source, target) = parse_install_args(std::env::args_os().skip(1));
    application().run(|cx: &mut App| {
        let options = gpui_window_options(
            "alpenglow.installer",
            "Alpenglow Installer",
            Some(gpui::WindowBounds::Windowed(bounds(
                point(gpui::px(140.), gpui::px(64.)),
                size(gpui::px(980.), gpui::px(660.)),
            ))),
            Some(size(gpui::px(840.), gpui::px(560.))),
        );
        if let Err(e) = cx.open_window(options, |_, cx| {
            cx.new(|_| InstallerView::new(source, target))
        }) {
            eprintln!("Failed to open window: {:?}", e);
            cx.quit();
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_disk_size() {
        // Zero sectors
        assert_eq!(format_disk_size(0), "0 MiB");

        // MiB range
        assert_eq!(format_disk_size(2048), "1 MiB");
        assert_eq!(format_disk_size(102400), "50 MiB");
        assert_eq!(format_disk_size(2097151), "1024 MiB");

        // GiB range (2097152 sectors = 1 GiB)
        assert_eq!(format_disk_size(2097152), "1.0 GiB");
        assert_eq!(format_disk_size(3145728), "1.5 GiB");
        assert_eq!(format_disk_size(5000000), "2.4 GiB");
        assert_eq!(format_disk_size(4194304), "2.0 GiB");

        // Large sectors testing saturating multiply
        // u64::MAX = 18446744073709551615
        // u64::MAX as f64 = 18446744073709551616.0
        // (u64::MAX as f64) / 1024.0 / 1024.0 / 1024.0 = 17179869184.0
        assert_eq!(format_disk_size(u64::MAX), "17179869184.0 GiB");
    }

    #[test]
    fn test_is_install_disk_name() {
        let valid_names = vec!["sda", "sdb1", "vda", "vdb", "xvda", "nvme0n1", "mmcblk0"];

        let invalid_names = vec![
            "loop0",
            "ram0",
            "zram0",
            "nvme0n1p1-loop",
            "sda-ram",
            "ttyS0",
            "sr0",
        ];

        for name in valid_names {
            assert!(
                is_install_disk_name(name),
                "Expected {} to be a valid install disk name",
                name
            );
        }

        for name in invalid_names {
            assert!(
                !is_install_disk_name(name),
                "Expected {} to be an invalid install disk name",
                name
            );
        }
    }
}

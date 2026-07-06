#[cfg(feature = "gui")]
fn main() {
    use alpenglow_installer::{install_image_maybe_compressed, parse_install_args};
    use crepuscularity_gpui::prelude::*;
    use gpui::{bounds, point, size, App, Application, ClickEvent};
    use std::fs;
    use std::path::PathBuf;

    struct InstallerView {
        source: PathBuf,
        target: Option<PathBuf>,
        disks: Vec<DiskChoice>,
        status: String,
    }

    #[derive(Clone)]
    struct DiskChoice {
        path: PathBuf,
        name: String,
        detail: String,
    }

    impl InstallerView {
        fn new(source: PathBuf, target: Option<PathBuf>) -> Self {
            let disks = discover_disks();
            let target = target.or_else(|| disks.first().map(|disk| disk.path.clone()));
            let status = target
                .as_ref()
                .map(|target| format!("Ready to install to {}", target.display()))
                .unwrap_or_else(|| {
                    "No install target found. Attach a disk or use the terminal installer."
                        .to_string()
                });
            Self {
                source,
                target,
                disks,
                status,
            }
        }

        fn refresh_disks(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.disks = discover_disks();
            if self.target.is_none() {
                self.target = self.disks.first().map(|disk| disk.path.clone());
            }
            self.status = self
                .target
                .as_ref()
                .map(|target| format!("Ready to install to {}", target.display()))
                .unwrap_or_else(|| "No install target found.".to_string());
            cx.notify();
        }

        fn select_disk(&mut self, index: usize, cx: &mut gpui::Context<Self>) {
            let Some(disk) = self.disks.get(index) else {
                self.status = "That disk is no longer available.".to_string();
                cx.notify();
                return;
            };
            self.target = Some(disk.path.clone());
            self.status = format!("Ready to install to {}", disk.path.display());
            cx.notify();
        }

        fn select_disk_0(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.select_disk(0, cx);
        }

        fn select_disk_1(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.select_disk(1, cx);
        }

        fn select_disk_2(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.select_disk(2, cx);
        }

        fn select_disk_3(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.select_disk(3, cx);
        }

        fn disk_label(&self, index: usize) -> String {
            self.disks
                .get(index)
                .map(|disk| disk.path.display().to_string())
                .unwrap_or_default()
        }

        fn disk_detail(&self, index: usize) -> String {
            self.disks
                .get(index)
                .map(|disk| disk.detail.clone())
                .unwrap_or_default()
        }

        fn install(&mut self, _: &ClickEvent, _: &mut gpui::Window, cx: &mut gpui::Context<Self>) {
            let Some(target) = self.target.as_ref() else {
                self.status = "Choose an install target first.".to_string();
                cx.notify();
                return;
            };
            match install_image_maybe_compressed(&self.source, target, false) {
                Ok(bytes) => self.status = format!("Wrote {bytes} bytes to {}", target.display()),
                Err(err) => self.status = format!("Install failed: {err}"),
            }
            cx.notify();
        }
    }

    impl gpui::Render for InstallerView {
        fn render(
            &mut self,
            _window: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) -> impl IntoElement {
            let source = self.source.display().to_string();
            let target = self
                .target
                .as_ref()
                .map(|target| target.display().to_string())
                .unwrap_or_else(|| "No target disk selected".to_string());
            let status = self.status.clone();
            let has_target = self.target.is_some();
            let disk_0 = self.disk_label(0);
            let disk_0_detail = self.disk_detail(0);
            let disk_1 = self.disk_label(1);
            let disk_1_detail = self.disk_detail(1);
            let disk_2 = self.disk_label(2);
            let disk_2_detail = self.disk_detail(2);
            let disk_3 = self.disk_label(3);
            let disk_3_detail = self.disk_detail(3);
            let has_disk_0 = self.disks.first().is_some();
            let has_disk_1 = self.disks.get(1).is_some();
            let has_disk_2 = self.disks.get(2).is_some();
            let has_disk_3 = self.disks.get(3).is_some();
            view! {r#"
                div bg-[#000000] text-[#ededed] size-full p-6 flex-col items-center justify-center font-[Geist]
                    div bg-[#0a0a0a] border border-[#333333] rounded shadow-lg w-[720px] flex-col overflow-hidden
                        div border-b border-[#333333] h-12 px-5 flex-row items-center justify-between
                            div flex-row items-center gap-3
                                div bg-[#ffffff] rounded w-4 h-4
                                div flex-col
                                    div text-base font-bold
                                        "Alpenglow Installer"
                                    div text-xs text-[#888888]
                                        "Desktop image writer"
                            div text-xs text-[#888888]
                                "Live session"
                        div p-5 flex-col gap-3
                            div flex-col gap-2
                                div text-2xl font-bold
                                    "Write release image"
                                div text-sm text-[#a1a1a1]
                                    "Choose a disk, review the source image, then install Alpenglow."
                            div flex-row gap-4
                                div border border-[#333333] rounded flex-col overflow-hidden flex-1
                                    div bg-[#111111] border-b border-[#333333] px-4 py-2 flex-row items-center justify-between
                                        div text-sm font-semibold
                                            "Target disk"
                                        button border border-[#333333] bg-[#0a0a0a] text-[#ededed] rounded px-3 py-1 text-xs @click=refresh_disks
                                            "Refresh"
                                    if {has_disk_0}
                                        button bg-[#0a0a0a] text-[#ededed] border-b border-[#333333] px-4 py-2 flex-row items-center justify-between @click=select_disk_0
                                            div flex-col gap-1
                                                div text-sm font-medium
                                                    "{disk_0}"
                                                div text-xs text-[#888888]
                                                    "{disk_0_detail}"
                                            div text-xs text-[#888888]
                                                "Select"
                                    if {has_disk_1}
                                        button bg-[#0a0a0a] text-[#ededed] border-b border-[#333333] px-4 py-2 flex-row items-center justify-between @click=select_disk_1
                                            div flex-col gap-1
                                                div text-sm font-medium
                                                    "{disk_1}"
                                                div text-xs text-[#888888]
                                                    "{disk_1_detail}"
                                            div text-xs text-[#888888]
                                                "Select"
                                    if {has_disk_2}
                                        button bg-[#0a0a0a] text-[#ededed] border-b border-[#333333] px-4 py-2 flex-row items-center justify-between @click=select_disk_2
                                            div flex-col gap-1
                                                div text-sm font-medium
                                                    "{disk_2}"
                                                div text-xs text-[#888888]
                                                    "{disk_2_detail}"
                                            div text-xs text-[#888888]
                                                "Select"
                                    if {has_disk_3}
                                        button bg-[#0a0a0a] text-[#ededed] px-4 py-2 flex-row items-center justify-between @click=select_disk_3
                                            div flex-col gap-1
                                                div text-sm font-medium
                                                    "{disk_3}"
                                                div text-xs text-[#888888]
                                                    "{disk_3_detail}"
                                            div text-xs text-[#888888]
                                                "Select"
                                    if {has_target}
                                        div px-4 py-2 text-xs text-[#888888]
                                            "The selected disk will be overwritten."
                                    else
                                        div px-4 py-2 text-sm text-[#888888]
                                            "No writable disk detected."
                                div border border-[#333333] rounded flex-col overflow-hidden flex-1
                                    div bg-[#111111] border-b border-[#333333] px-4 py-2 text-sm font-semibold
                                        "Install plan"
                                    div px-4 py-2 flex-col gap-1
                                        div text-xs text-[#888888]
                                            "Source"
                                        div text-sm text-[#ededed]
                                            "{source}"
                                    div bg-[#333333] h-[1px]
                                    div px-4 py-2 flex-col gap-1
                                        div text-xs text-[#888888]
                                            "Target"
                                        div text-sm text-[#ededed]
                                            "{target}"
                            div border border-[#333333] rounded flex-col overflow-hidden
                                div px-4 py-2 flex-row gap-4 items-start
                                    div text-xs text-[#888888] w-20
                                        "Status"
                                    div text-sm text-[#d4d4d4] flex-1
                                        "{status}"
                            div flex-row items-center justify-between gap-4
                                div text-xs text-[#888888] flex-1
                                    "Standard images use the terminal installer; desktop images open this window from Alpenglowed."
                                if {has_target}
                                    button bg-[#ffffff] text-[#000000] font-bold rounded px-5 py-2 @click=install
                                        "Install"
                                else
                                    div text-sm text-[#888888]
                                        "alpenglow-install-tui /run/alpenglow/alpenglow.img.zst /dev/sdX"
            "#}
        }
    }

    fn discover_disks() -> Vec<DiskChoice> {
        let mut disks = fs::read_dir("/sys/block")
            .ok()
            .into_iter()
            .flat_map(|entries| entries.filter_map(Result::ok))
            .filter_map(|entry| {
                let name = entry.file_name().to_string_lossy().to_string();
                if !is_install_disk_name(&name) {
                    return None;
                }
                let path = PathBuf::from("/dev").join(&name);
                if !path.exists() {
                    return None;
                }
                let size = fs::read_to_string(entry.path().join("size")).ok();
                let model = fs::read_to_string(entry.path().join("device/model"))
                    .ok()
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty());
                let detail = match (
                    model,
                    size.and_then(|value| value.trim().parse::<u64>().ok()),
                ) {
                    (Some(model), Some(sectors)) => {
                        format!("{model} - {}", format_disk_size(sectors))
                    }
                    (Some(model), None) => model,
                    (None, Some(sectors)) => format_disk_size(sectors),
                    (None, None) => "Block device".to_string(),
                };
                Some(DiskChoice {
                    path,
                    name: name.to_string(),
                    detail,
                })
            })
            .collect::<Vec<_>>();
        disks.sort_by(|left, right| left.name.cmp(&right.name));
        disks
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

    fn format_disk_size(sectors: u64) -> String {
        let bytes = sectors.saturating_mul(512);
        let gib = bytes as f64 / 1024.0 / 1024.0 / 1024.0;
        if gib >= 1.0 {
            format!("{gib:.1} GiB")
        } else {
            let mib = bytes as f64 / 1024.0 / 1024.0;
            format!("{mib:.0} MiB")
        }
    }

    let (source, target) = parse_install_args(std::env::args_os().skip(1));
    Application::new().run(|cx: &mut App| {
        let options = gpui_window_options(
            "alpenglow.installer",
            "Alpenglow Installer",
            Some(gpui::WindowBounds::Windowed(bounds(
                point(gpui::px(220.), gpui::px(72.)),
                size(gpui::px(800.), gpui::px(560.)),
            ))),
            Some(size(gpui::px(720.), gpui::px(500.))),
        );
        cx.open_window(options, |_, cx| {
            cx.new(|_| InstallerView::new(source, target))
        })
        .unwrap();
    });
}

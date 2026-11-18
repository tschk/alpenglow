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
    use alpenglow_installer::{
        inspect_install_disk, install_image_to_disk, parse_install_args, DiskIdentity,
    };
    use crepuscularity_gpui::prelude::*;
    use gpui::{bounds, point, size, App, Application, ClickEvent};
    use std::fs;
    use std::path::PathBuf;

    struct InstallerView {
        source: PathBuf,
        target: Option<DiskIdentity>,
        disks: Vec<DiskChoice>,
        status: String,
        confirmation: String,
        input_focus: gpui::FocusHandle,
    }

    #[derive(Clone)]
    struct DiskChoice {
        identity: DiskIdentity,
        name: String,
        detail: String,
    }

    impl InstallerView {
        fn new(source: PathBuf, cx: &mut gpui::Context<Self>) -> Self {
            let disks = discover_disks();
            Self {
                source,
                target: None,
                disks,
                status: "Choose a disk to continue.".into(),
                confirmation: String::new(),
                input_focus: cx.focus_handle(),
            }
        }

        fn refresh_disks(
            &mut self,
            _: &ClickEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            self.disks = discover_disks();
            self.target = None;
            self.confirmation.clear();
            self.status = "Choose a disk to continue.".into();
            cx.notify();
        }

        fn select_disk(&mut self, index: usize, cx: &mut gpui::Context<Self>) {
            let Some(disk) = self.disks.get(index) else {
                self.status = "That disk is no longer available.".to_string();
                cx.notify();
                return;
            };
            self.target = Some(disk.identity.clone());
            self.confirmation.clear();
            self.status = "Review the disk and type its name to confirm.".into();
            cx.notify();
        }

        fn input_key_down(
            &mut self,
            event: &gpui::KeyDownEvent,
            _: &mut gpui::Window,
            cx: &mut gpui::Context<Self>,
        ) {
            let key = &event.keystroke;
            if key.modifiers.control || key.modifiers.platform {
                return;
            }
            if key.key == "backspace" {
                self.confirmation.pop();
            } else if let Some(text) = &key.key_char {
                if !text.chars().any(char::is_control) {
                    self.confirmation.push_str(text);
                }
            }
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
                .map(|disk| disk.identity.path.display().to_string())
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
            match install_image_to_disk(&self.source, target, &self.confirmation) {
                Ok(bytes) => {
                    self.status = format!("Wrote {bytes} bytes to {}", target.path.display())
                }
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
                .map(|disk| {
                    format!(
                        "{} — {} — {} — {}",
                        disk.path.display(),
                        disk.model,
                        format_disk_size(disk.size_bytes / 512),
                        if disk.removable {
                            "Removable"
                        } else {
                            "Not removable"
                        }
                    )
                })
                .unwrap_or_else(|| "No target disk selected".to_string());
            let required_name = self
                .target
                .as_ref()
                .and_then(|disk| disk.path.file_name())
                .and_then(|name| name.to_str())
                .unwrap_or("")
                .to_string();
            let confirmation_text = if self.confirmation.is_empty() {
                "Click here and type the device name".to_string()
            } else {
                self.confirmation.clone()
            };
            let confirmation_input = gpui::div()
                .track_focus(&self.input_focus)
                .on_key_down(cx.listener(Self::input_key_down))
                .border_1()
                .p_2()
                .child(confirmation_text);
            let status = self.status.clone();
            let has_target = self.target.is_some();
            let can_install = has_target && self.confirmation == required_name;
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
            let content = view! {r#"
                div bg-[#000000] text-[#ededed] p-4 flex flex-col items-center font-[Geist]
                    div bg-[#050505] border border-[#262626] rounded shadow-lg w-[940px] flex flex-col overflow-hidden
                        div border-b border-[#262626] h-14 px-6 flex flex-row items-center gap-3
                            div bg-[#ffffff] rounded w-4 h-4
                            div text-lg font-semibold
                                "Alpenglow Installer"
                        div p-4 flex flex-col gap-2
                            div flex flex-row items-center gap-3
                                div bg-[#ffffff] text-[#000000] rounded px-4 py-2 text-sm font-bold
                                    "1 Choose disk"
                                div border border-[#333333] text-[#a1a1a1] rounded px-4 py-2 text-sm
                                    "2 Review"
                                div border border-[#333333] text-[#a1a1a1] rounded px-4 py-2 text-sm
                                    "3 Install"
                            div flex flex-row items-end justify-between gap-6
                                div text-3xl font-bold
                                    "Select disk"
                                div text-sm text-[#9a9a9a]
                                    "This will overwrite the selected disk."
                            div border border-[#2f2f2f] rounded overflow-hidden flex flex-col
                                div bg-[#101010] border-b border-[#2f2f2f] px-5 py-2 flex flex-row items-center justify-between
                                    div flex flex-col gap-1
                                        div text-sm font-semibold
                                            "Available disks"
                                        div text-xs text-[#8a8a8a]
                                            "Detected from /sys/block"
                                    button border border-[#3a3a3a] bg-[#050505] text-[#ededed] rounded px-4 py-2 text-xs @click=refresh_disks
                                        "Refresh"
                                if {has_disk_0}
                                    button bg-[#050505] text-[#ededed] border-b border-[#262626] px-5 py-3 flex flex-row items-center justify-between @click=select_disk_0
                                        div flex flex-col gap-1
                                            div text-base font-semibold
                                                "{disk_0}"
                                            div text-xs text-[#8a8a8a]
                                                "{disk_0_detail}"
                                        div border border-[#3a3a3a] rounded px-3 py-1 text-xs text-[#d4d4d4]
                                            "Choose"
                                if {has_disk_1}
                                    button bg-[#050505] text-[#ededed] border-b border-[#262626] px-5 py-3 flex flex-row items-center justify-between @click=select_disk_1
                                        div flex flex-col gap-1
                                            div text-base font-semibold
                                                "{disk_1}"
                                            div text-xs text-[#8a8a8a]
                                                "{disk_1_detail}"
                                        div border border-[#3a3a3a] rounded px-3 py-1 text-xs text-[#d4d4d4]
                                            "Choose"
                                if {has_disk_2}
                                    button bg-[#050505] text-[#ededed] border-b border-[#262626] px-5 py-3 flex flex-row items-center justify-between @click=select_disk_2
                                        div flex flex-col gap-1
                                            div text-base font-semibold
                                                "{disk_2}"
                                            div text-xs text-[#8a8a8a]
                                                "{disk_2_detail}"
                                        div border border-[#3a3a3a] rounded px-3 py-1 text-xs text-[#d4d4d4]
                                            "Choose"
                                if {has_disk_3}
                                    button bg-[#050505] text-[#ededed] px-5 py-3 flex flex-row items-center justify-between @click=select_disk_3
                                        div flex flex-col gap-1
                                            div text-base font-semibold
                                                "{disk_3}"
                                            div text-xs text-[#8a8a8a]
                                                "{disk_3_detail}"
                                        div border border-[#3a3a3a] rounded px-3 py-1 text-xs text-[#d4d4d4]
                                            "Choose"
                            div border border-[#2f2f2f] rounded p-4 flex flex-col gap-2
                                div text-xs text-[#8a8a8a]
                                    "Source"
                                div text-sm text-[#ededed]
                                    "{source}"
                                div text-xs text-[#8a8a8a]
                                    "Target"
                                div text-sm text-[#ededed]
                                    "{target}"
                                if {has_target}
                                    div text-sm text-[#fca5a5]
                                        "Everything on this disk will be destroyed. Type {required_name} to confirm:"
                                    {confirmation_input}
                                div text-xs text-[#8a8a8a]
                                    "Status"
                                div text-sm text-[#ededed]
                                    "{status}"
                            div border-t border-[#262626] pt-4 flex flex-row items-center justify-between
                                div text-xs text-[#777777]
                                    "No changes are made until Install is clicked."
                                if {can_install}
                                    button bg-[#ffffff] text-[#000000] font-bold rounded px-6 py-3 @click=install
                                        "Install"
                                else if {has_target}
                                    div text-sm text-[#888888]
                                        "Type the device name to continue"
                                else
                                    div text-sm text-[#888888]
                                        "Choose a disk to continue"
            "#};
            gpui::div()
                .id("installer-scroll")
                .size_full()
                .bg(gpui::black())
                .overflow_y_scroll()
                .child(content)
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
                    let identity = inspect_install_disk(&path).ok()?;
                    let detail = format!(
                        "{} - {} - {}",
                        identity.model,
                        format_disk_size(identity.size_bytes / 512),
                        if identity.removable {
                            "Removable"
                        } else {
                            "Not removable"
                        }
                    );
                    Some(DiskChoice {
                        identity,
                        name,
                        detail,
                    })
                }));
            }
            handles
                .into_iter()
                .filter_map(|h| h.join().ok().flatten())
                .collect::<Vec<_>>()
        });

        disks.sort_by(|left, right| left.name.cmp(&right.name));
        disks
    }

    let (source, _) = parse_install_args(std::env::args_os().skip(1));
    Application::new().run(|cx: &mut App| {
        let options = gpui_window_options(
            "alpenglow.installer",
            "Alpenglow Installer",
            Some(gpui::WindowBounds::Windowed(bounds(
                point(gpui::px(140.), gpui::px(64.)),
                size(gpui::px(1040.), gpui::px(700.)),
            ))),
            Some(size(gpui::px(940.), gpui::px(620.))),
        );
        if let Err(e) = cx.open_window(options, |_, cx| cx.new(|cx| InstallerView::new(source, cx)))
        {
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

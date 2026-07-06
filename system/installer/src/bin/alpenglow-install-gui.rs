#[cfg(feature = "gui")]
fn main() {
    use alpenglow_installer::{install_image_maybe_compressed, parse_install_args};
    use crepuscularity_gpui::prelude::*;
    use gpui::{bounds, point, size, App, Application, ClickEvent};
    use std::path::PathBuf;

    struct InstallerView {
        source: PathBuf,
        target: Option<PathBuf>,
        status: String,
    }

    impl InstallerView {
        fn new(source: PathBuf, target: Option<PathBuf>) -> Self {
            let status = target
                .as_ref()
                .map(|target| format!("Ready to install to {}", target.display()))
                .unwrap_or_else(|| {
                    "Pass target disk as second argument: alpenglow-install-gui <image> <disk>"
                        .to_string()
                });
            Self {
                source,
                target,
                status,
            }
        }

        fn install(&mut self, _: &ClickEvent, _: &mut gpui::Window, cx: &mut gpui::Context<Self>) {
            let Some(target) = self.target.as_ref() else {
                self.status =
                    "No target disk. Run alpenglow-install-gui <image> <disk>.".to_string();
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
            view! {r#"
                div bg-[#101014] text-[#f4f4f5] size-full p-6 flex-col gap-4
                    div text-xl font-bold
                        "Alpenglow Installer"
                    div text-sm text-[#a1a1aa]
                        "Write the release image to a target disk."
                    div border border-[#3f3f46] rounded p-4 flex-col gap-2
                        div text-sm text-[#d4d4d8]
                            "Source: {source}"
                        div text-sm text-[#d4d4d8]
                            "Target: {target}"
                        div text-sm text-[#facc15]
                            "{status}"
                    if {has_target}
                        button bg-[#22c55e] text-[#052e16] font-bold rounded px-4 py-2 @click=install
                            "Install Alpenglow"
                    else
                        div text-sm text-[#facc15]
                            "alpenglow-install-tui /run/alpenglow/alpenglow.img.zst /dev/sdX"
            "#}
        }
    }

    let (source, target) = parse_install_args(std::env::args_os().skip(1));
    Application::new().run(|cx: &mut App| {
        let options = gpui_window_options(
            "alpenglow.installer",
            "Alpenglow Installer",
            Some(gpui::WindowBounds::Windowed(bounds(
                point(gpui::px(80.), gpui::px(80.)),
                size(gpui::px(760.), gpui::px(460.)),
            ))),
            Some(size(gpui::px(620.), gpui::px(360.))),
        );
        cx.open_window(options, |_, cx| {
            cx.new(|_| InstallerView::new(source, target))
        })
        .unwrap();
    });
}

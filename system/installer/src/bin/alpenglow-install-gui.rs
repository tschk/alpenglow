#[cfg(feature = "gui")]
fn main() {
    use crepuscularity_gpui::prelude::*;
    use gpui::{bounds, point, size, App, Application};

    struct InstallerView;

    impl gpui::Render for InstallerView {
        fn render(
            &mut self,
            _window: &mut gpui::Window,
            _cx: &mut gpui::Context<Self>,
        ) -> impl IntoElement {
            view! {r#"
                div bg-[#101014] text-[#f4f4f5] size-full p-6 flex-col gap-4
                    div text-xl font-bold
                        "Alpenglow Installer"
                    div text-sm text-[#a1a1aa]
                        "Write the release image to a target disk."
                    div border border-[#3f3f46] rounded p-4 flex-col gap-2
                        div font-bold
                            "Desktop installer"
                        div text-sm text-[#d4d4d8]
                            "Use the terminal installer for disk writes until the GPUI event layer is wired."
                        div text-sm text-[#facc15]
                            "alpenglow-install-tui /run/alpenglow/alpenglow.img.zst /dev/sdX"
            "#}
        }
    }

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
        cx.open_window(options, |_, cx| cx.new(|_| InstallerView))
            .unwrap();
    });
}

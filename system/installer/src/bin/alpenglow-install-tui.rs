use alpenglow_installer::install_image_maybe_compressed;
use crepuscularity_tui::{ratatui, Template};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::path::PathBuf;

const UI: &str = include_str!("../../ui/tui.crepus");

fn main() {
    let mut args = std::env::args_os().skip(1);
    let source = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/run/alpenglow/alpenglow.img.zst"));
    let target = args.next().map(PathBuf::from);
    if let Err(err) = draw(&source, target.as_ref()) {
        eprintln!("installer ui failed: {err}");
        std::process::exit(1);
    }
    if let Some(target) = target {
        match install_image_maybe_compressed(&source, &target, false) {
            Ok(bytes) => println!("wrote {bytes} bytes to {}", target.display()),
            Err(err) => {
                eprintln!("install failed: {err}");
                std::process::exit(1);
            }
        }
    }
}

fn draw(source: &PathBuf, target: Option<&PathBuf>) -> Result<(), String> {
    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = Terminal::new(backend).map_err(|err| err.to_string())?;
    let mut ui = Template::from_source(UI);
    ui.set("source", source.display().to_string());
    ui.set(
        "target",
        target
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| "pass target disk as second argument".to_string()),
    );
    terminal
        .draw(|frame| {
            let _ = ui.draw_full(frame);
        })
        .map_err(|err| err.to_string())?;
    Ok(())
}

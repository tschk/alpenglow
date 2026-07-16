use crepuscularity_tui::{ratatui, Template};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::path::Path;

const UI: &str = include_str!("../ui/tui.crepus");

pub fn draw_installer_tui(source: &Path, target: Option<&Path>) -> Result<(), String> {
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
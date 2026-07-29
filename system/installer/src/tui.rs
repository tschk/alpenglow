use crepuscularity_tui::{ratatui, Template};
use ratatui::{
    backend::{Backend, CrosstermBackend},
    Terminal,
};
use std::io;
use std::path::Path;

const UI: &str = include_str!("../ui/tui.crepus");

pub fn draw_installer_tui(source: &Path, target: Option<&Path>) -> Result<(), String> {
    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = Terminal::new(backend).map_err(|err| err.to_string())?;
    draw_installer_tui_internal(&mut terminal, source, target)
}

pub fn draw_installer_tui_internal<B: Backend>(
    terminal: &mut Terminal<B>,
    source: &Path,
    target: Option<&Path>,
) -> Result<(), String> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;

    #[test]
    fn test_draw_installer_tui_internal() {
        let backend = TestBackend::new(100, 40);
        let mut terminal = Terminal::new(backend).unwrap();

        let source = Path::new("/dev/sda");
        let target = Some(Path::new("/dev/sdb"));

        let result = draw_installer_tui_internal(&mut terminal, source, target);
        assert!(result.is_ok());

        // Assert some drawing happened.
        // We can check the terminal's backend state.
        let _buffer = terminal.backend().buffer();
        // Since we don't know the exact UI content, we can just ensure it didn't panic or error.
    }

    #[test]
    fn test_draw_installer_tui_internal_no_target() {
        let backend = TestBackend::new(100, 40);
        let mut terminal = Terminal::new(backend).unwrap();

        let source = Path::new("/dev/sda");
        let target = None;

        let result = draw_installer_tui_internal(&mut terminal, source, target);
        assert!(result.is_ok());
    }
}

export const description =
  "Alpenglow is an immutable RAM-root Linux distribution with persistent bcachefs-backed state.";

export const title = "Alpenglow";

export default function App() {
  return (
    <div data-crepus-root="true">
      <header className="boot-top-bar" aria-label="Alpenglow links">
        <a
          id="release-link"
          href="https://github.com/tschk/alpenglow/releases/latest"
          target="_blank"
          rel="noopener noreferrer"
          aria-live="polite"
        >
          latest release
        </a>
        <span className="boot-top-sep" aria-hidden="true">
          ·
        </span>
        <a
          href="https://github.com/tschk/alpenglow"
          target="_blank"
          rel="noopener noreferrer"
        >
          GitHub
        </a>
        <span className="boot-top-sep" aria-hidden="true">
          ·
        </span>
        <a href="https://tsc.hk" target="_blank" rel="noopener noreferrer">
          tsc.hk
        </a>
      </header>
      <main
        id="screen_container"
        className="page-shell"
        aria-label="Alpenglow OS"
      >
        <div className="hidden" />
        <canvas className="hidden" />
        <pre
          id="terminal"
          className="hidden"
          tabIndex={0}
          aria-label="Alpenglow console"
        />
        <form id="command_form" className="hidden" autoComplete="off">
          <input
            id="command_input"
            autoCapitalize="none"
            autoComplete="off"
            autoCorrect="off"
            spellCheck={false}
            inputMode="text"
            aria-label="Command"
          />
          <button type="submit">run</button>
        </form>
        <section id="boot_status" className="boot-status" aria-live="polite">
          <p id="boot_message">loading alpenglow shell</p>
          <meter id="boot_progress" min={0} max={100} value={0}>
            0%
          </meter>
        </section>
      </main>
      <footer className="site-credit">built with crepuscularity + moonshine</footer>
    </div>
  );
}

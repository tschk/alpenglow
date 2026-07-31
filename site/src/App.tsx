import type { CSSProperties } from "react";

const monoFont = '"Geist Mono", ui-monospace, monospace';

const leadText =
  "Alpenglow is an immutable RAM-root Linux distribution with persistent bcachefs-backed state.";

const linkStyle: CSSProperties = {
  color: "#fafafa",
  textDecoration: "underline",
  textUnderlineOffset: "3px",
};

const sepStyle: CSSProperties = {
  color: "#52525b",
  userSelect: "none",
};

const navStyle: CSSProperties = {
  position: "fixed",
  top: "clamp(14px, 2.4vw, 30px)",
  right: "clamp(14px, 2.4vw, 30px)",
  zIndex: "11",
  display: "flex",
  flexWrap: "wrap",
  alignItems: "center",
  justifyContent: "flex-end",
  gap: "0.35rem 0.5rem",
  fontFamily: monoFont,
  fontSize: "clamp(0.75rem, 1.6vw, 0.9rem)",
  color: "#a1a1aa",
  pointerEvents: "auto",
};

const mainStyle: CSSProperties = {
  margin: "0",
  height: "100vh",
  overflow: "hidden",
  background: "#000",
  color: "#fff",
  fontFamily: monoFont,
  WebkitFontSmoothing: "antialiased",
  display: "flex",
  flexDirection: "column",
};

const leadStyle: CSSProperties = {
  padding: "clamp(28px, 5vw, 64px)",
  color: "#e4e4e7",
  fontSize: "clamp(0.875rem, 2vw, 1.125rem)",
};

const bootStyle: CSSProperties = {
  position: "fixed",
  bottom: "clamp(14px, 2.4vw, 30px)",
  left: "clamp(14px, 2.4vw, 30px)",
  right: "clamp(14px, 2.4vw, 30px)",
  zIndex: "10",
  display: "grid",
  gap: "0.625rem",
  maxWidth: "130",
  fontFamily: monoFont,
  pointerEvents: "none",
};

const meterStyle: CSSProperties = {
  height: "0.75rem",
  width: "100%",
  accentColor: "#fff",
};

export default function App() {
  return (
    <div data-crepus-root="true">
      <link rel="modulepreload" href="/shell.js" />
      <script type="module" src="/shell.js" />
      <div style={navStyle}>
        <a
          href="https://github.com/tschk/alpenglow/releases/latest"
          target="_blank"
          rel="noopener noreferrer"
          style={linkStyle}
        >
          latest release
        </a>
        <span style={sepStyle}>·</span>
        <a
          href="https://github.com/tschk/alpenglow"
          target="_blank"
          rel="noopener noreferrer"
          style={linkStyle}
        >
          GitHub
        </a>
        <span style={sepStyle}>·</span>
        <a
          href="https://tsc.hk"
          target="_blank"
          rel="noopener noreferrer"
          style={linkStyle}
        >
          tsc.hk
        </a>
      </div>
      <div style={mainStyle}>
        <span style={leadStyle}>{leadText}</span>
      </div>
      <div style={bootStyle}>
        <span style={{ margin: "0", color: "#fff" }}>
          loading alpenglow shell
        </span>
        <meter value={0} min={0} max={100} style={meterStyle} />
      </div>
    </div>
  );
}

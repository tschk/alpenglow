export const globalCss = `@font-face {
  font-family: "Geist Mono";
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url("/fonts/geist-mono-latin-400-normal.woff2") format("woff2");
}

:root {
  color-scheme: dark;
  font-family: "Geist Mono", ui-monospace, monospace;
}

html,
body {
  margin: 0;
  height: 100%;
  overflow: hidden;
  background: #000;
  color: #fff;
  -webkit-font-smoothing: antialiased;
}

.boot-top-bar {
  position: fixed;
  top: clamp(14px, 2.4vw, 30px);
  right: clamp(14px, 2.4vw, 30px);
  z-index: 11;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 0.35rem 0.5rem;
  font-family: "Geist Mono", ui-monospace, monospace;
  font-size: clamp(0.75rem, 1.6vw, 0.9rem);
  color: #a1a1aa;
  pointer-events: auto;
}

.boot-top-bar a {
  color: #fafafa;
  text-decoration: underline;
  text-underline-offset: 3px;
}

.boot-top-bar a:hover {
  color: #fff;
}

.boot-top-sep {
  color: #52525b;
  user-select: none;
}

.page-shell {
  position: fixed;
  inset: 0;
  width: 100%;
  height: 100%;
  overflow: hidden;
  background: #000;
  color: #fff;
}

.hidden {
  display: none;
}

.boot-status {
  pointer-events: none;
  position: fixed;
  bottom: clamp(14px, 2.4vw, 30px);
  left: clamp(14px, 2.4vw, 30px);
  right: clamp(14px, 2.4vw, 30px);
  z-index: 10;
  display: grid;
  gap: 0.625rem;
  max-width: 32.5rem;
  font-family: "Geist Mono", ui-monospace, monospace;
  font-size: 0.75rem;
  line-height: 1.375;
}

.boot-status p {
  margin: 0;
  color: #fff;
}

.boot-status meter {
  height: 0.75rem;
  width: 100%;
  accent-color: #fff;
}

#boot_status[hidden] {
  display: none !important;
}

.site-credit {
  position: fixed;
  bottom: clamp(14px, 2.4vw, 30px);
  right: clamp(14px, 2.4vw, 30px);
  z-index: 11;
  font-family: "Geist Mono", ui-monospace, monospace;
  font-size: clamp(0.7rem, 1.4vw, 0.8rem);
  color: #52525b;
  pointer-events: none;
}

#xterm_host {
  position: fixed;
  inset: 0;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  min-height: 100dvh;
  min-width: 100vw;
  padding: clamp(28px, 5vw, 64px);
  background: #000;
}

#xterm_host canvas {
  display: block;
  width: 100% !important;
  height: 100% !important;
}

/* ghostty/xterm hidden input caret at (0,0) */
#xterm_host textarea {
  position: fixed !important;
  left: -10000px !important;
  top: 0 !important;
  width: 1px !important;
  height: 1px !important;
  opacity: 0 !important;
  caret-color: transparent !important;
  overflow: hidden !important;
  z-index: -1 !important;
}
`;

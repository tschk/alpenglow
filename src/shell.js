import { init, Terminal, FitAddon } from "ghostty-web";

const bootStatus = document.getElementById("boot_status");
const bootMessage = document.getElementById("boot_message");
const bootProgress = document.getElementById("boot_progress");
const screen = document.getElementById("screen_container");
const legacyPre = document.getElementById("terminal");
const commandForm = document.getElementById("command_form");
const commandInput = document.getElementById("command_input");

let buildId = "dev";
try {
  const idRes = await fetch("/v86/initrd-build-id.txt", { cache: "no-store" });
  if (idRes.ok) {
    buildId = (await idRes.text()).trim() || buildId;
  }
} catch {
  /* ignore */
}

const asset = (path) => `${path}?v=${encodeURIComponent(buildId)}`;
let emulator;
let term;
let fitAddon;

function setStatus(message, percent) {
  if (bootMessage) {
    bootMessage.textContent = message;
  }
  if (bootProgress && Number.isFinite(percent)) {
    bootProgress.value = Math.max(0, Math.min(100, percent));
    bootProgress.textContent = `${Math.round(bootProgress.value)}%`;
  }
}

function finishStatus(message) {
  setStatus(message, 100);
  setTimeout(() => {
    if (bootStatus) {
      bootStatus.hidden = true;
    }
    applyTerminalScale();
  }, 700);
}

function sendSerial(data) {
  emulator?.serial0_send(data);
}

function terminalFontSize() {
  const w = window.innerWidth;
  const h = window.innerHeight;
  const pad = Math.min(72, Math.max(24, Math.min(w, h) * 0.06));
  const innerW = Math.max(200, w - pad * 2);
  const innerH = Math.max(120, h - pad * 2);
  const cols = Math.max(48, Math.floor(innerW / 8.2));
  const rows = Math.max(14, Math.floor(innerH / 18));
  const fromWidth = innerW / cols;
  const fromHeight = innerH / rows;
  return Math.min(26, Math.max(11, Math.round(Math.min(fromWidth, fromHeight) * 0.92)));
}

function applyTerminalScale() {
  if (!term || !fitAddon) {
    return;
  }
  const size = terminalFontSize();
  if (term.options && term.options.fontSize !== size) {
    term.options.fontSize = size;
  }
  fitAddon.fit();
}

async function mountTerminal() {
  if (!screen) {
    return false;
  }
  if (legacyPre) {
    legacyPre.hidden = true;
  }
  if (commandForm) {
    commandForm.hidden = true;
  }

  await init();

  let host = document.getElementById("xterm_host");
  if (!host) {
    host = document.createElement("div");
    host.id = "xterm_host";
    host.className = "term-host";
    host.setAttribute("aria-label", "Alpenglow serial console");
    screen.appendChild(host);
  }

  term = new Terminal({
    fontSize: terminalFontSize(),
    fontFamily: '"Geist Mono", ui-monospace, monospace',
    cursorBlink: true,
    scrollback: 10000,
    theme: {
      background: "#000000",
      foreground: "#f2f2f2",
      cursor: "#ffffff",
    },
  });

  fitAddon = new FitAddon();
  term.loadAddon(fitAddon);
  term.open(host);
  applyTerminalScale();
  if (fitAddon.observeResize) {
    fitAddon.observeResize();
  }
  window.addEventListener("resize", () => applyTerminalScale());

  term.writeln("Alpenglow loading…");
  term.focus();
  term.onData(sendSerial);
  host.addEventListener("pointerdown", () => term.focus());
  return true;
}

function wireLegacyKeyboard() {
  if (!legacyPre) {
    return;
  }
  legacyPre.hidden = false;
  legacyPre.style.display = "block";
  legacyPre.textContent = "Alpenglow loading…\n";
  legacyPre.focus();

  commandForm?.addEventListener("submit", (e) => {
    e.preventDefault();
    const line = commandInput?.value ?? "";
    if (commandInput) {
      commandInput.value = "";
    }
    sendSerial(`${line}\r`);
    legacyPre.focus();
  });

  legacyPre.addEventListener("keydown", (event) => {
    if (event.metaKey || event.altKey) {
      return;
    }
    if (event.ctrlKey) {
      const key = event.key.toLowerCase();
      if (key >= "a" && key <= "z") {
        sendSerial(String.fromCharCode(key.charCodeAt(0) - 96));
        event.preventDefault();
      }
      return;
    }
    const keys = { Enter: "\r", Backspace: "\x7F", Tab: "\t" };
    if (keys[event.key]) {
      sendSerial(keys[event.key]);
      event.preventDefault();
      return;
    }
    if (event.key.length === 1) {
      sendSerial(event.key);
      event.preventDefault();
    }
  });
}

if (!screen) {
  throw new Error("Alpenglow shell mount point is missing");
}

setStatus("loading Alpenglow", 0);
const useXterm = await mountTerminal();

try {
  const { V86 } = await import(asset("/v86/libv86.mjs"));

  emulator = new V86({
    wasm_path: asset("/v86/v86.wasm"),
    screen_container: null,
    bios: { url: asset("/v86/seabios.bin") },
    vga_bios: { url: asset("/v86/vgabios.bin") },
    bzimage: { url: asset("/v86/alpenglow-v86-vmlinuz") },
    initrd: { url: asset("/v86/alpenglow-v86-initrd.cpio.gz") },
    cmdline: "console=ttyS0 rdinit=/init quiet",
    memory_size: 256 * 1024 * 1024,
    autostart: true,
  });

  emulator.add_listener("serial0-output-byte", (byte) => {
    const ch = String.fromCharCode(byte);
    if (term) {
      term.write(ch);
      return;
    }
    if (legacyPre) {
      legacyPre.textContent += ch;
      legacyPre.scrollTop = legacyPre.scrollHeight;
    }
  });

  if (!useXterm) {
    wireLegacyKeyboard();
  }

  emulator.add_listener("download-progress", (event) => {
    if (event.lengthComputable && event.total) {
      const percent = ((event.file_index + event.loaded / event.total) / event.file_count) * 100;
      setStatus(`loading Alpenglow ${Math.round(percent)}%`, percent);
      return;
    }
    setStatus("loading Alpenglow", bootProgress?.value || 0);
  });

  emulator.add_listener("download-error", (event) => {
    setStatus("failed to load Alpenglow", bootProgress?.value || 0);
    console.error("v86 download error", event);
  });

  emulator.add_listener("emulator-ready", () => {
    finishStatus("booting alpenglow shell");
    applyTerminalScale();
    term?.focus();
  });
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  setStatus(`failed: ${message}`, bootProgress?.value || 0);
  term?.writeln(`\r\nAlpenglow failed to start: ${message}`);
  if (legacyPre) {
    legacyPre.textContent += `\nAlpenglow failed to start: ${message}\n`;
  }
  throw error;
}
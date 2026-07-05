const terminal = document.getElementById("terminal");
const commandForm = document.getElementById("command_form");
const commandInput = document.getElementById("command_input");
const screen = document.getElementById("screen_container");
const bootStatus = document.getElementById("boot_status");
const bootMessage = document.getElementById("boot_message");
const bootProgress = document.getElementById("boot_progress");
const assetVersion = "20260705-os-docs";
const asset = (path) => `${path}?v=${assetVersion}`;
const ansiPattern = /\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1B\\)|[@-Z\\-_])/g;
const urlPattern = /https:\/\/[^\s<>"')]+/g;
let terminalText = "";
let emulator;

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
  }, 700);
}

function writeTerminal(text) {
  terminalText = (terminalText + text)
    .replace(ansiPattern, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "")
    .replace("/bin/sh: can't access tty; job control turned off\n", "");

  terminal.innerHTML = terminalText
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(urlPattern, (url) => `<a href="${url}" target="_blank" rel="noreferrer">${url}</a>`);
  terminal.scrollTop = terminal.scrollHeight;
}

function sendInput(data) {
  if (emulator) {
    emulator.serial0_send(data);
  }
}

if (!terminal || !screen) {
  throw new Error("Alpenglow shell mount point is missing");
}

terminal.focus();
writeTerminal("Alpenglow loading...\n");
setStatus("loading Alpenglow", 0);

terminal.addEventListener("pointerdown", () => terminal.focus());
commandForm?.addEventListener("submit", (event) => {
  event.preventDefault();
  const command = commandInput?.value || "";
  if (commandInput) {
    commandInput.value = "";
  }
  sendInput(`${command}\r`);
  terminal.focus();
});

terminal.addEventListener("keydown", (event) => {
  if (event.metaKey || event.altKey) {
    return;
  }

  if (event.ctrlKey) {
    const key = event.key.toLowerCase();
    if (key >= "a" && key <= "z") {
      sendInput(String.fromCharCode(key.charCodeAt(0) - 96));
      event.preventDefault();
    }
    return;
  }

  const keys = {
    Enter: "\r",
    Backspace: "\x7F",
    Tab: "\t",
  };

  if (keys[event.key]) {
    sendInput(keys[event.key]);
    event.preventDefault();
    return;
  }

  if (event.key.length === 1) {
    sendInput(event.key);
    event.preventDefault();
  }
});

try {
  const { V86 } = await import("/v86/libv86.mjs");

  emulator = new V86({
    wasm_path: asset("/v86/v86.wasm"),
    screen_container: null,
    bios: { url: asset("/v86/seabios.bin") },
    vga_bios: { url: asset("/v86/vgabios.bin") },
    bzimage: { url: asset("/v86/alpenglow-v86-vmlinuz") },
    initrd: { url: asset("/v86/alpenglow-v86-initrd.cpio.gz") },
    cmdline: "console=ttyS0 rdinit=/init quiet",
    memory_size: 128 * 1024 * 1024,
    autostart: true,
  });

  emulator.add_listener("serial0-output-byte", (byte) => {
    writeTerminal(String.fromCharCode(byte));
  });

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
  });

  emulator.add_listener("emulator-ready", () => {
    finishStatus("booting alpenglow shell");
  });
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  writeTerminal(`\nAlpenglow failed to start: ${message}\n`);
  setStatus(`failed: ${message}`, bootProgress?.value || 0);
  throw error;
}

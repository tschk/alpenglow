const bootStatus = document.getElementById("boot_status");
const bootMessage = document.getElementById("boot_message");
const bootProgress = document.getElementById("boot_progress");
const screen = document.getElementById("screen_container");
const legacyPre = document.getElementById("terminal");

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
  }, 700);
}

function prepareHost() {
  if (!screen) {
    throw new Error("Alpenglow shell mount point is missing");
  }
  if (legacyPre) {
    legacyPre.hidden = true;
  }
  let host = document.getElementById("xterm_host");
  if (!host) {
    host = document.createElement("div");
    host.id = "xterm_host";
    host.setAttribute("aria-label", "Alpenglow serial console");
    screen.appendChild(host);
  }
  if (window.FitAddon?.FitAddon) {
    fitAddon = new window.FitAddon.FitAddon();
  }
  const ro = new ResizeObserver(() => fitAddon?.fit?.());
  ro.observe(host);
  return host;
}

if (!screen) {
  throw new Error("Alpenglow shell mount point is missing");
}

setStatus("loading Alpenglow", 0);
const xtermHost = window.Terminal ? prepareHost() : null;

try {
  const { V86 } = await import(asset("/v86/libv86.mjs"));

  const v86Opts = {
    wasm_path: asset("/v86/v86.wasm"),
    screen_container: null,
    bios: { url: asset("/v86/seabios.bin") },
    vga_bios: { url: asset("/v86/vgabios.bin") },
    bzimage: { url: asset("/v86/alpenglow-v86-vmlinuz") },
    initrd: { url: asset("/v86/alpenglow-v86-initrd.cpio.gz") },
    cmdline: "console=ttyS0 rdinit=/init quiet",
    memory_size: 128 * 1024 * 1024,
    autostart: true,
  };

  if (xtermHost) {
    v86Opts.serial_container_xtermjs = xtermHost;
  }

  emulator = new V86(v86Opts);

  if (!xtermHost && legacyPre) {
    legacyPre.hidden = false;
    legacyPre.style.display = "block";
    legacyPre.textContent = "Alpenglow loading...\n";
    emulator.add_listener("serial0-output-byte", (byte) => {
      legacyPre.textContent += String.fromCharCode(byte);
      legacyPre.scrollTop = legacyPre.scrollHeight;
    });
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
    fitAddon?.fit?.();
    const termEl = xtermHost?.querySelector?.(".xterm-helper-textarea");
    termEl?.focus?.();
  });
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  setStatus(`failed: ${message}`, bootProgress?.value || 0);
  if (legacyPre) {
    legacyPre.hidden = false;
    legacyPre.textContent += `\nAlpenglow failed to start: ${message}\n`;
  }
  throw error;
}
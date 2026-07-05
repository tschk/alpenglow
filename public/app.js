const serial = document.getElementById("serial");
const screen = document.getElementById("screen_container");
const bootStatus = document.getElementById("boot_status");
const bootMessage = document.getElementById("boot_message");
const bootProgress = document.getElementById("boot_progress");
const assetVersion = "20260705-shell-progress";
const asset = (path) => `${path}?v=${assetVersion}`;

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

if (!serial || !screen) {
  throw new Error("Alpenglow shell mount point is missing");
}

serial.value = "Alpenglow shell loading...\n";
setStatus("loading v86", 0);

try {
  const { V86 } = await import("/v86/libv86.mjs");

  const emulator = new V86({
    wasm_path: asset("/v86/v86.wasm"),
    screen_container: screen,
    serial_container: serial,
    bios: { url: asset("/v86/seabios.bin") },
    vga_bios: { url: asset("/v86/vgabios.bin") },
    bzimage: { url: asset("/v86/alpenglow-v86-vmlinuz") },
    initrd: { url: asset("/v86/alpenglow-v86-initrd.cpio.gz") },
    cmdline: "console=ttyS0 rdinit=/init quiet",
    memory_size: 128 * 1024 * 1024,
    autostart: true,
  });

  emulator.add_listener("download-progress", (event) => {
    if (event.lengthComputable && event.total) {
      const percent = ((event.file_index + event.loaded / event.total) / event.file_count) * 100;
      setStatus(`loading ${event.file_name || "v86"} ${Math.round(percent)}%`, percent);
      return;
    }

    setStatus(`loading ${event.file_name || "v86"}`, bootProgress?.value || 0);
  });

  emulator.add_listener("download-error", (event) => {
    setStatus(`failed to load ${event.file_name || "v86 asset"}`, bootProgress?.value || 0);
  });

  emulator.add_listener("emulator-ready", () => {
    finishStatus("booting alpenglow shell");
  });
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  serial.value += `\nAlpenglow failed to start: ${message}\n`;
  setStatus(`failed: ${message}`, bootProgress?.value || 0);
  throw error;
}

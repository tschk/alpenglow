const docName = document.getElementById("doc-name");
const docContent = document.getElementById("doc-content");
const bootMessage = document.getElementById("boot-message");

async function loadDoc(file) {
  docName.textContent = file;
  bootMessage.textContent = `fetch /home/${file}\nalpenglow: home ready, no auth required`;
  const response = await fetch(`/home/${file}`);
  docContent.textContent = await response.text();
}

for (const button of document.querySelectorAll("[data-doc]")) {
  button.addEventListener("click", () => loadDoc(button.dataset.doc));
}

loadDoc("welcome.md").catch((error) => {
  docContent.textContent = String(error);
});

let emulator;
const startButton = document.getElementById("start-vm");
const vmStatus = document.getElementById("vm-status");

startButton.addEventListener("click", async () => {
  if (emulator) {
    emulator.run();
    vmStatus.textContent = "running";
    return;
  }

  startButton.disabled = true;
  vmStatus.textContent = "loading emulator";
  const { V86 } = await import("/v86/libv86.mjs");
  emulator = new V86({
    wasm_path: "/v86/v86.wasm",
    screen_container: document.getElementById("screen_container"),
    serial_container: document.getElementById("serial"),
    bios: { url: "/v86/seabios.bin" },
    vga_bios: { url: "/v86/vgabios.bin" },
    bzimage: { url: "/v86/alpenglow-v86-vmlinuz" },
    initrd: { url: "/v86/alpenglow-v86-initrd.cpio.gz" },
    cmdline: "console=ttyS0 rdinit=/init quiet",
    memory_size: 128 * 1024 * 1024,
    autostart: true,
  });
  emulator.add_listener("emulator-ready", () => {
    vmStatus.textContent = "running";
    startButton.disabled = false;
    startButton.textContent = "Resume VM";
  });
});

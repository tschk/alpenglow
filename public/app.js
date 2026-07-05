const serial = document.getElementById("serial");

serial.value = "Alpenglow shell booting...\n";

const { V86 } = await import("/v86/libv86.mjs");

new V86({
  wasm_path: "/v86/v86.wasm",
  screen_container: document.getElementById("screen_container"),
  serial_container: serial,
  bios: { url: "/v86/seabios.bin" },
  vga_bios: { url: "/v86/vgabios.bin" },
  bzimage: { url: "/v86/alpenglow-v86-vmlinuz" },
  initrd: { url: "/v86/alpenglow-v86-initrd.cpio.gz" },
  cmdline: "console=ttyS0 rdinit=/init quiet",
  memory_size: 128 * 1024 * 1024,
  autostart: true,
});

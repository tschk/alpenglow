import { defineConfig, presetUno } from "unocss";

export default defineConfig({
  presets: [presetUno()],
  shortcuts: {
    "page-shell": "fixed inset-0 w-full h-full overflow-hidden bg-black text-white",
    "font-mono-ui": "font-mono text-xs leading-snug",
    "term-host":
      "fixed inset-0 box-border flex flex-col min-h-100dvh min-w-100vw bg-black p-[clamp(28px,5vw,64px)]",
  },
});
import { defineConfig } from "astro/config";
import UnoCSS from "unocss/astro";

export default defineConfig({
  output: "static",
  site: "https://alpenglow.tsc.hk",
  integrations: [UnoCSS()],
});
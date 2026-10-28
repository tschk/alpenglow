import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("styles", () => {
  test("exports a string", () => {
    expect(typeof globalCss).toBe("string");
  });

  test("contains @font-face definition for Geist Mono", () => {
    expect(globalCss).toContain("@font-face");
    expect(globalCss).toContain('font-family: "Geist Mono"');
    expect(globalCss).toContain('src: url("/fonts/geist-mono-latin-400-normal.woff2")');
  });

  test("contains main selectors and variables", () => {
    expect(globalCss).toContain(":root");
    expect(globalCss).toContain("color-scheme: dark;");
    expect(globalCss).toContain("html,\nbody {");
    expect(globalCss).toContain(".boot-top-bar {");
    expect(globalCss).toContain(".page-shell {");
    expect(globalCss).toContain(".boot-status {");
    expect(globalCss).toContain(".site-credit {");
    expect(globalCss).toContain("#xterm_host {");
  });

  test("hides hidden elements and layers the boot UI", () => {
    expect(globalCss).toContain(".hidden {\n  display: none;\n}");
    expect(globalCss).toContain("#boot_status[hidden] {\n  display: none !important;\n}");
    expect(globalCss).toContain("z-index: 10;");
    expect(globalCss).toContain("pointer-events: auto;");
  });

  test("includes xterm host child styles", () => {
    expect(globalCss).toContain("#xterm_host canvas {");
    expect(globalCss).toContain("#xterm_host textarea {");
  });

  test("defines the boot top bar separator", () => {
    expect(globalCss).toContain(".boot-top-sep {");
  });
});

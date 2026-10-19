import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("styles", () => {
  test("globalCss exports correct styles string", () => {
    // Basic structural checks
    expect(globalCss).toContain("@font-face {");
    expect(globalCss).toContain(":root {");
    expect(globalCss).toContain("html,");
    expect(globalCss).toContain("body {");

    // Font configurations
    expect(globalCss).toContain('font-family: "Geist Mono";');
    expect(globalCss).toContain('src: url("/fonts/geist-mono-latin-400-normal.woff2") format("woff2");');

    // Root variables/settings
    expect(globalCss).toContain("color-scheme: dark;");

    // Core structural classes
    expect(globalCss).toContain(".boot-top-bar {");
    expect(globalCss).toContain(".page-shell {");
    expect(globalCss).toContain(".boot-status {");
    expect(globalCss).toContain(".site-credit {");
    expect(globalCss).toContain("#xterm_host {");

    // Ensure hidden classes are correctly defined
    expect(globalCss).toContain(".hidden {\n  display: none;\n}");
    expect(globalCss).toContain("#boot_status[hidden] {\n  display: none !important;\n}");

    // Check specific critical properties
    expect(globalCss).toContain("background: #000;");
    expect(globalCss).toContain("color: #fff;");
    expect(globalCss).toContain("z-index: 11;");
    expect(globalCss).toContain("z-index: 10;");
    expect(globalCss).toContain("pointer-events: none;");
    expect(globalCss).toContain("pointer-events: auto;");
  });
});

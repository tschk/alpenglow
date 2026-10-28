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
});

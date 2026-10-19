import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("globalCss", () => {
  test("contains essential global styles", () => {
    expect(typeof globalCss).toBe("string");
    expect(globalCss).toContain("@font-face");
    expect(globalCss).toContain('font-family: "Geist Mono"');
    expect(globalCss).toContain(":root");
    expect(globalCss).toContain("color-scheme: dark;");
    expect(globalCss).toContain("html,");
    expect(globalCss).toContain("body");
    expect(globalCss).toContain("margin: 0;");
    expect(globalCss).toContain("background: #000;");
  });

  test("contains layout and UI component styles", () => {
    expect(globalCss).toContain(".boot-top-bar");
    expect(globalCss).toContain(".page-shell");
    expect(globalCss).toContain(".boot-status");
    expect(globalCss).toContain(".site-credit");
    expect(globalCss).toContain("#xterm_host");
  });
});

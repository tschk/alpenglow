import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("styles", () => {
  test("exports globalCss string", () => {
    expect(typeof globalCss).toBe("string");
    expect(globalCss.length).toBeGreaterThan(0);
  });

  test("globalCss includes font-face definition", () => {
    expect(globalCss).toContain("@font-face {");
    expect(globalCss).toContain('font-family: "Geist Mono";');
    expect(globalCss).toContain('src: url("/fonts/geist-mono-latin-400-normal.woff2") format("woff2");');
  });

  test("globalCss includes root variables", () => {
    expect(globalCss).toContain(":root {");
    expect(globalCss).toContain("color-scheme: dark;");
  });

  test("globalCss includes html/body reset", () => {
    expect(globalCss).toContain("html,\nbody {");
    expect(globalCss).toContain("margin: 0;");
    expect(globalCss).toContain("overflow: hidden;");
  });

  test("globalCss includes boot UI styles", () => {
    expect(globalCss).toContain(".boot-top-bar {");
    expect(globalCss).toContain(".boot-status {");
    expect(globalCss).toContain(".site-credit {");
  });

  test("globalCss includes xterm host styles", () => {
    expect(globalCss).toContain("#xterm_host {");
    expect(globalCss).toContain("#xterm_host canvas {");
    expect(globalCss).toContain("#xterm_host textarea {");
  });
});

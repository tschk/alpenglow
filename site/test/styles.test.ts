import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("styles", () => {
  test("exports globalCss string with expected styles", () => {
    expect(typeof globalCss).toBe("string");
    expect(globalCss).toContain("@font-face {");
    expect(globalCss).toContain("font-family: \"Geist Mono\";");
    expect(globalCss).toContain(":root {");
    expect(globalCss).toContain(".boot-top-bar {");
    expect(globalCss).toContain(".page-shell {");
    expect(globalCss).toContain(".boot-status {");
  });
});

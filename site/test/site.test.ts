import { describe, expect, test } from "bun:test";
import { createBunServer } from "@tschk/moonshine-deploy-bun";
import { tryServeStatic } from "@tschk/moonshine-server";
import { resolve } from "node:path";
import { buildSite } from "../src/build";
import { renderDocument, renderResponse } from "../src/document";

const outDir = resolve(import.meta.dir, "..", "dist");
const staticDir = await buildSite(outDir);

async function handler(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const pathname = url.pathname.replace(/\/+$/, "") || "/";

  if (pathname === "/") {
    return renderResponse(request);
  }

  if (request.method === "GET" || request.method === "HEAD") {
    const staticRes = await tryServeStatic(staticDir, pathname);
    if (staticRes) return staticRes;
  }

  return new Response("Not Found", { status: 404 });
}

describe("alpenglow site", () => {
  test("GET / returns 200 with HTML", async () => {
    const server = createBunServer({ fetch: handler, port: 0, staticDir });
    try {
      const res = await fetch(`${server.url.origin}/`);
      expect(res.status).toBe(200);
      expect(res.headers.get("content-type")).toContain("text/html");
      const html = await res.text();
      expect(html).toContain("<!DOCTYPE html>");
      expect(html).toContain('<html lang="en">');
      expect(html).toContain("<title>Alpenglow</title>");
      expect(html).toContain(
        "Alpenglow is an immutable RAM-root Linux distribution with persistent bcachefs-backed state.",
      );
      expect(html).toContain("loading alpenglow shell");
      expect(html).toContain("latest release");
      expect(html).toContain(
        "https://github.com/tschk/alpenglow/releases/latest",
      );
      expect(html).toContain("https://tsc.hk");
      expect(html).toContain("<meter");
      expect(html).toContain("/shell.js");
      expect(html).toContain("built with crepuscularity + moonshine");
    } finally {
      await server.stop(true);
    }
  });

  test("carries every element the shell mounts against", async () => {
    const html = await renderDocument(new Request("http://localhost/"));
    for (const id of [
      "screen_container",
      "terminal",
      "boot_status",
      "boot_message",
      "boot_progress",
      "command_form",
      "command_input",
      "release-link",
    ]) {
      expect(html).toContain(`id="${id}"`);
    }
  });

  test("serves the bundled shell without bare imports", async () => {
    const server = createBunServer({ fetch: handler, port: 0, staticDir });
    try {
      const res = await fetch(`${server.url.origin}/shell.js`);
      expect(res.status).toBe(200);
      const source = await res.text();
      expect(source).not.toMatch(/^import[\s\S]*?["']ghostty-web["']/m);
    } finally {
      await server.stop(true);
    }
  });

  test("builds a deployable dist with the v86 assets", async () => {
    expect(await Bun.file(resolve(outDir, "index.html")).exists()).toBe(true);
    expect(await Bun.file(resolve(outDir, "shell.js")).exists()).toBe(true);
    expect(await Bun.file(resolve(outDir, "_headers")).exists()).toBe(true);
    expect(await Bun.file(resolve(outDir, "v86", "v86.wasm")).exists()).toBe(
      true,
    );
  });

  test("unknown path returns 404", async () => {
    const server = createBunServer({ fetch: handler, port: 0, staticDir });
    try {
      const res = await fetch(`${server.url.origin}/nope`);
      expect(res.status).toBe(404);
    } finally {
      await server.stop(true);
    }
  });

  test("renderResponse returns a valid Response object", async () => {
    const req = new Request("http://localhost/");
    const res = await renderResponse(req);
    expect(res).toBeInstanceOf(Response);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
  });
});

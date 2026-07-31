import { describe, expect, test } from "bun:test";
import { createBunServer } from "@tschk/moonshine-deploy-bun";
import { reactRenderer } from "@tschk/moonshine-react";
import type {
  RenderContext,
  RouteArtifact,
} from "@tschk/moonshine-framework";
import { tryServeStatic } from "@tschk/moonshine-server";
import { resolve } from "node:path";

const staticDir = resolve(import.meta.dir, "public");

const route: RouteArtifact = {
  id: "home",
  path: "/",
  file: resolve(import.meta.dir, "..", "src", "App.tsx"),
  mode: "static",
  runtime: "bun",
  decision: "test",
  clientEntries: ["/shell.js"],
};

async function handler(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const pathname = url.pathname.replace(/\/+$/, "") || "/";

  if (pathname === "/") {
    const ctx: RenderContext = {
      request,
      route,
      params: {},
      data: null,
      signal: request.signal,
    };
    return reactRenderer.render(ctx);
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
    } finally {
      await server.stop(true);
    }
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
});

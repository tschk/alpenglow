import { describe, expect, test } from "bun:test";
import { createBunServer } from "@tschk/moonshine-deploy-bun";
import { crepusRenderer } from "@tschk/crepus-moonshine";
import type {
  RenderContext,
  RouteArtifact,
} from "@tschk/moonshine-framework";
import { tryServeStatic } from "@tschk/moonshine-server";
import { resolve } from "node:path";
import { pageIr } from "../src/ir";

const staticDir = resolve(import.meta.dir, "public");

const route: RouteArtifact = {
  id: "home",
  path: "/",
  file: "ir.ts",
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
      data: pageIr,
      signal: request.signal,
    };
    return crepusRenderer.render(ctx);
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
      expect(html).toContain("Alpenglow");
    } finally {
      await server.stop(true);
    }
  });
});

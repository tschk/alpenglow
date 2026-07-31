import { createBunServer } from "@tschk/moonshine-deploy-bun";
import { reactRenderer } from "@tschk/moonshine-react";
import type {
  RenderContext,
  RouteArtifact,
} from "@tschk/moonshine-framework";
import { tryServeStatic } from "@tschk/moonshine-server";
import { resolve } from "node:path";

const staticDir = resolve(import.meta.dir, "public");
const port = Number(process.env.PORT) || 3000;

const route: RouteArtifact = {
  id: "home",
  path: "/",
  file: resolve(import.meta.dir, "App.tsx"),
  mode: "static",
  runtime: "bun",
  decision: "server",
  clientEntries: ["/shell.js"],
};

async function fetch(request: Request): Promise<Response> {
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

const server = createBunServer({ fetch, port, staticDir });

console.log(`Alpenglow site running on ${server.url.origin}`);

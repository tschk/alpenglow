import { createBunServer } from "@tschk/moonshine-deploy-bun";
import { tryServeStatic } from "@tschk/moonshine-server";
import { buildSite } from "./build";
import { renderResponse } from "./document";

const port = Number(process.env.PORT) || 3000;
const staticDir = await buildSite();

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

const server = createBunServer({ fetch: handler, port, staticDir });

console.log(`Alpenglow site running on ${server.url.origin}`);

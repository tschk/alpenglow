import { createBunServer } from "@tschk/moonshine-deploy-bun";
import { buildSite } from "./build";
import { createHandler } from "./handler";

const port = Number(process.env.PORT) || 3000;
const staticDir = await buildSite();

export const handler = createHandler(staticDir);

export let server: ReturnType<typeof createBunServer> | undefined;
if (import.meta.main) {
  server = createBunServer({ fetch: handler, port, staticDir });
  console.log(`Alpenglow site running on ${server.url.origin}`);
}

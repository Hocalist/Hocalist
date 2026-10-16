import { createPushWorkerHandler } from "./handler.ts";

Deno.serve(createPushWorkerHandler({
  env: (name) => Deno.env.get(name),
  fetch,
}));

// Hocalist commercial worker: provider-neutral payout execution bridge.
//
// This function never names, calls or emulates a payout provider. It runs the
// reviewed claim/reconcile/poll state machine only when a verified provider
// adapter is installed; until then it reports that state honestly.
import { createHandler } from "./handler.ts";

Deno.serve(createHandler({
  fetcher: fetch,
  env: (name) => Deno.env.get(name),
}));

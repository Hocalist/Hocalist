import { evidenceRoute } from "../../lib/admin-route";

// Narrow evidence gateway. The reference check and any URL resolution happen
// server-side; no bucket, storage path or service-role key reaches the client.
export async function POST(request: Request) {
  return evidenceRoute(request);
}

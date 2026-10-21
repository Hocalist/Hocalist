import { adminRpcRoute } from "../../lib/admin-route";

// Browser-facing bridge for reviewed admin RPCs. The access token stays in an
// httpOnly cookie; the server authorization check remains in the database.
export async function POST(request: Request) {
  return adminRpcRoute(request);
}

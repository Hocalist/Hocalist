import { sessionRefreshRoute } from "../../../lib/admin-route";

// Recovers an absent or expired access cookie from the refresh cookie before a
// page render; rotation is persisted here where cookies can be set.
export async function GET(request: Request) {
  return sessionRefreshRoute(request);
}

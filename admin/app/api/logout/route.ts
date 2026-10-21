import { logoutRoute } from "../../lib/admin-route";

export async function POST(request: Request) {
  return logoutRoute(request);
}

export async function GET(request: Request) {
  return logoutRoute(request);
}

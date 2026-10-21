import { loginRoute } from "../../lib/admin-route";

export async function POST(request: Request) {
  return loginRoute(request);
}

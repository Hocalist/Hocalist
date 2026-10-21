import { mfaCancelRoute } from "../../../lib/admin-route";

export async function POST(request: Request) {
  return mfaCancelRoute(request);
}

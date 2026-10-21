import { mfaPendingRoute } from "../../../lib/admin-route";

export async function POST(request: Request) {
  return mfaPendingRoute(request);
}

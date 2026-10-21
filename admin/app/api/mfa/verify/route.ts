import { mfaVerifyRoute } from "../../../lib/admin-route";

export async function POST(request: Request) {
  return mfaVerifyRoute(request);
}

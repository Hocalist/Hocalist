import { mfaChallengeRoute } from "../../../lib/admin-route";

export async function POST(request: Request) {
  return mfaChallengeRoute(request);
}

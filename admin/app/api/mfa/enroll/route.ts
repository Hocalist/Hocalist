import { coreRequest, coreDeps, coreResponse } from '../../../lib/admin-route';
import { enrollAdminMfa } from '../../../lib/admin-mfa-enrollment';
export async function POST(request: Request) {
  const response = coreResponse(await enrollAdminMfa(await coreRequest(request), coreDeps()), request);
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}

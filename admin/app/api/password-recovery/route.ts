import { coreRequest,coreDeps,coreResponse } from '../../lib/admin-route';
import { passwordRecovery } from '../../lib/admin-password-recovery';
export async function POST(request:Request){
 const response=coreResponse(await passwordRecovery(await coreRequest(request),coreDeps()),request);
 response.headers.set('Cache-Control','no-store');
 return response;
}

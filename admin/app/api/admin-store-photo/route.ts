import {coreRequest,coreDeps,coreResponse} from "../../lib/admin-route";
import {handleEvidenceCore} from "../../lib/admin-http";
import {storeImageResolver} from "../../lib/admin-media-evidence";
export async function POST(request:Request) {
 return coreResponse(await handleEvidenceCore(await coreRequest(request),coreDeps(),storeImageResolver,"store"),request);
}

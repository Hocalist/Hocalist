// Authenticate the exact review reference with the original signed user JWT.
// The service key is used only for the already-authorized private object read.
export function createEvidenceReader(project:string,service:string,fetcher:typeof fetch=fetch,scope:"verification"|"store"="verification"){
 const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
 return async(authorization:string,submissionId:string,mediaId:string):Promise<Uint8Array>=>{
  const ref=await fetcher(`${project}/rest/v1/rpc/${scope==="store"?"admin_store_image":"admin_evidence_image"}`,{
   method:'POST',redirect:'error',headers:{apikey:service,Authorization:authorization,'Content-Type':'application/json','Content-Profile':'hocalist'},
   body:JSON.stringify({p_submission:submissionId,p_media:mediaId}),signal:AbortSignal.timeout(10000),
  });
  if(!ref.ok){await ref.body?.cancel();throw Error('evidence_denied');}
  const image=await ref.json();
  if(image?.id!==mediaId||image?.state!=='ready'||typeof image?.owner_user_id!=='string'||!uuid.test(image.owner_user_id))throw Error('evidence_denied');
  const response=await fetcher(`${project}/storage/v1/object/hocalist-images/${image.owner_user_id}/${mediaId}.jpg`,{
   redirect:'error',headers:{apikey:service,Authorization:`Bearer ${service}`},signal:AbortSignal.timeout(10000),
  });
  if(!response.ok||!response.body||response.headers.get('content-type')?.split(';')[0]!=='image/jpeg'){await response.body?.cancel();throw Error('evidence_unavailable');}
  const reader=response.body.getReader(),chunks:Uint8Array[]=[];let size=0;
  while(true){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>4*1024*1024){await reader.cancel();throw Error('evidence_unavailable');}chunks.push(next.value);}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  if(size<3||bytes[0]!==255||bytes[1]!==216||bytes[2]!==255)throw Error('evidence_unavailable');
  return bytes;
 };
}

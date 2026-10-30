export interface ImageGateway {
  authenticate(token:string):Promise<string|null>;
  rpc(user:string,action:string,input:Record<string,unknown>):Promise<{id:string;path:string;state:string}>;
  sanitize(bytes:Uint8Array):{bytes:Uint8Array;width:number;height:number};
  store(path:string,bytes:Uint8Array):Promise<void>;
  read(path:string):Promise<Uint8Array>;
}
const MAX=4*1024*1024;
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export function createMediaHandler(deps:ImageGateway){return async(req:Request):Promise<Response>=>{
 if(req.method!=='POST')return json({error:'method_not_allowed'},405);
 try{
  const auth=req.headers.get('authorization')??'';
  if(!auth.startsWith('Bearer '))return json({error:'unauthorized'},401);
  const user=await deps.authenticate(auth);if(!user)return json({error:'unauthorized'},401);
  const action=new URL(req.url).searchParams.get('action');
  if(action==='read'){
   const id=new URL(req.url).searchParams.get('id')??'';
   if(!uuid.test(id))return json({error:'invalid_input'},400);
   const item=await deps.rpc(user,'read',{id});
   const bytes=await deps.read(item.path);
   return new Response(new Uint8Array(bytes).buffer,{headers:{'Content-Type':'image/jpeg','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
  }
  if(action!=='upload'||req.headers.get('content-type')!=='image/jpeg')return json({error:'jpeg_required'},400);
  const key=req.headers.get('x-upload-key')??'';const purpose=req.headers.get('x-media-purpose')??'';
  if(!uuid.test(key)||!['offer','store','profile','chat','review','report','request','purchase_review'].includes(purpose))return json({error:'invalid_input'},400);
  if(Number(req.headers.get('content-length'))>MAX)return json({error:'too_large'},413);
  const reader=req.body?.getReader();if(!reader)return json({error:'empty_image'},400);
  const chunks:Uint8Array[]=[];let size=0;
  while(true){const item=await reader.read();if(item.done)break;size+=item.value.length;if(size>MAX){await reader.cancel();return json({error:'too_large'},413);}chunks.push(item.value);}
  const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
  if(size<4||bytes[0]!==255||bytes[1]!==216)return json({error:'invalid_image'},400);
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(v=>v.toString(16).padStart(2,'0')).join('');
  const item=await deps.rpc(user,'begin',{key,purpose,hash});
  if(item.state==='ready')return json({id:item.id});
  let clean;try{clean=deps.sanitize(bytes);}catch{return json({error:'invalid_image'},400);}
  if(clean.bytes.length>MAX||clean.width>2048||clean.height>2048)return json({error:'too_large'},413);
  await deps.store(item.path,clean.bytes);
  await deps.rpc(user,'complete',{id:item.id,size:clean.bytes.length,width:clean.width,height:clean.height});
  return json({id:item.id});
 }catch{return json({error:'media_unavailable'},503);}
};}

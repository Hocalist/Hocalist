import {sanitizeImage} from './sanitize.ts';
import {createMediaHandler} from './handler.ts';
import {createPlacesAuthVerifier} from '../hocalist-places/auth.ts';
import {mediaCors} from './cors.ts';
const project='https://icqwbzswokoulatomgql.supabase.co';
const bucket='hocalist-images';
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return mediaCors(req);
 if(req.headers.has('Origin')&&req.headers.get('Origin')!=='http://127.0.0.1:7359')return mediaCors(req);
 const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
 if(Deno.env.get('HOCALIST_MEDIA_ENABLED')!=='true'||Deno.env.get('SUPABASE_URL')!==project||!service)return mediaCors(req,new Response(null,{status:404}));
 const headers={apikey:service,Authorization:`Bearer ${service}`};
 const verify=createPlacesAuthVerifier(project,service);
 return mediaCors(req,await createMediaHandler({
  authenticate:async token=>{const r=await verify(token);return 'userId' in r?r.userId:null;},
  rpc:async(user,action,input)=>{
   const r=await fetch(`${project}/rest/v1/rpc/media_gateway`,{method:'POST',headers:{...headers,'Content-Type':'application/json','Content-Profile':'hocalist'},body:JSON.stringify({p_user:user,p_action:action,p_input:input}),signal:AbortSignal.timeout(10000)});
   if(!r.ok){await r.body?.cancel();throw Error('rpc_failed');}return await r.json();
  },
  sanitize:sanitizeImage,
  store:async(path,bytes)=>{
   const r=await fetch(`${project}/storage/v1/object/${bucket}/${path}`,{method:'POST',headers:{...headers,'Content-Type':'image/jpeg','x-upsert':'true'},body:bytes,signal:AbortSignal.timeout(20000)});
   if(!r.ok){await r.body?.cancel();throw Error('storage_failed');}await r.body?.cancel();
  },
  read:async path=>{
   const r=await fetch(`${project}/storage/v1/object/${bucket}/${path}`,{headers,signal:AbortSignal.timeout(10000)});
   if(!r.ok){await r.body?.cancel();throw Error('storage_failed');}return new Uint8Array(await r.arrayBuffer());
  },
 })(req));
});

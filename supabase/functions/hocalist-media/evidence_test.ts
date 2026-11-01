import {createEvidenceReader} from './evidence.ts';
import {createMediaHandler,type ImageGateway} from './handler.ts';
const id='80000000-0000-4000-8000-000000000001',owner='80000000-0000-4000-8000-000000000002';
const check=(v:unknown)=>{if(!v)throw Error('assertion_failed');};
Deno.test('evidence reader uses user JWT for exact review authorization before storage',async()=>{
 const calls:string[]=[];
 const f:typeof fetch=async(input,init)=>{
  const options=init as RequestInit|undefined;
  calls.push(String(input));const auth=new Headers(options?.headers).get('Authorization');
  if(calls.length===1){check(auth==='Bearer user-session');check(JSON.parse(String(options?.body)).p_submission===owner);return Response.json({id,owner_user_id:owner,state:'ready'});}
  check(auth==='Bearer server-secret');check(String(input).endsWith(`${owner}/${id}.jpg`));
  return new Response(new Uint8Array([255,216,255,217]),{headers:{'Content-Type':'image/jpeg'}});
 };
 check((await createEvidenceReader('https://example.test','server-secret',f)('Bearer user-session',owner,id)).length===4);check(calls.length===2);
});
Deno.test('denied or mismatched evidence never reaches storage',async()=>{
 for(const result of [new Response(null,{status:403}),Response.json({id:owner,owner_user_id:owner,state:'ready'}),Response.json({id,owner_user_id:'../other',state:'ready'})]){
  let calls=0;let denied=false;
  try{await createEvidenceReader('https://example.test','secret',async()=>{calls++;return result;})('Bearer user',owner,id);}catch{denied=true;}
  check(denied&&calls===1);
 }
});
Deno.test('evidence endpoint requires both IDs, passes original session, hides failures',async()=>{
 let reads=0;
 const deps:ImageGateway={authenticate:async()=>owner,rpc:async()=>{throw Error('ordinary_gateway_must_not_run');},sanitize:()=>{throw Error();},store:async()=>{},read:async()=>{throw Error();},readEvidence:async(auth,submission,media)=>{reads++;check(auth==='Bearer user');check(submission===owner&&media===id);return new Uint8Array([255,216,255,217]);}};
 const req=(query:string)=>new Request(`https://example.test?action=evidence&${query}`,{method:'POST',headers:{Authorization:'Bearer user'}});
 const handler=createMediaHandler(deps);check((await handler(req(`id=${id}`))).status===400);check(reads===0);
 const ok=await handler(req(`id=${id}&submission_id=${owner}`));check(ok.status===200&&ok.headers.get('Cache-Control')==='no-store');
 deps.readEvidence=async()=>{throw Error('private-secret');};const bad=await handler(req(`id=${id}&submission_id=${owner}`));check(bad.status===503&&!(await bad.text()).includes('private-secret'));
});
Deno.test('Store photo endpoint uses only the Store review reader',async()=>{
 let reads=0;
 const deps:ImageGateway={authenticate:async()=>owner,rpc:async()=>{throw Error('wrong_gateway');},sanitize:()=>{throw Error();},store:async()=>{},read:async()=>{throw Error();},readEvidence:async()=>{throw Error('wrong_scope');},readStoreEvidence:async(auth,listing,media)=>{reads++;check(auth==='Bearer user'&&listing===owner&&media===id);return new Uint8Array([255,216,255,217]);}};
 const req=new Request(`https://example.test?action=store-evidence&id=${id}&submission_id=${owner}`,{method:'POST',headers:{Authorization:'Bearer user'}});
 check((await createMediaHandler(deps)(req)).status===200);check(reads===1);
});
Deno.test('Store image bytes are fetched only after exact Store authorization',async()=>{
 let calls=0;
 const f:typeof fetch=async(input,init)=>{calls++;
 if(calls===1){check(String(input).endsWith('/rpc/admin_store_image'));check(new Headers((init as RequestInit|undefined)?.headers).get('Authorization')==='Bearer user');return Response.json({id,owner_user_id:owner,state:'ready'});}
 return new Response(new Uint8Array([255,216,255,217]),{headers:{'Content-Type':'image/jpeg'}});};
 check((await createEvidenceReader('https://example.test','secret',f,'store')('Bearer user',owner,id)).length===4);check(calls===2);
});

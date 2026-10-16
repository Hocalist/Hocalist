import {createMediaHandler, type ImageGateway} from './handler.ts';
const assert=(value:unknown)=>{if(!value)throw Error('assertion_failed');};
const id='80000000-0000-4000-8000-000000000001';
const deps=():ImageGateway=>({authenticate:async()=> 'a',rpc:async()=>({id,path:`a/${id}.jpg`,state:'pending'}),
 sanitize:bytes=>({bytes,width:10,height:10}),store:async()=>{},read:async()=>new Uint8Array([255,216,255,217])});
const request=(bytes=new Uint8Array([255,216,255,217]),purpose='offer')=>new Request('https://example.test?action=upload',{method:'POST',headers:{authorization:'Bearer synthetic','content-type':'image/jpeg','x-upload-key':id,'x-media-purpose':purpose},body:bytes});
Deno.test('signed out never reads the request body or calls storage',async()=>{
 const d=deps();d.authenticate=async()=>null;d.rpc=async()=>{throw Error('must_not_call');};
 assert((await createMediaHandler(d)(request())).status===401);
});
Deno.test('review and report evidence purposes are accepted',async()=>{
 const d=deps();const h=createMediaHandler(d);
 assert((await h(request(undefined,'review'))).status===200);
 assert((await h(request(undefined,'report'))).status===200);
});
Deno.test('unknown upload purposes are rejected before metadata',async()=>{
 const d=deps();d.rpc=async()=>{throw Error('must_not_call');};
 assert((await createMediaHandler(d)(request(undefined,'evidence'))).status===400);
});
Deno.test('profile and chat uploads require UUID media keys, not marketplace text keys',async()=>{
 for(const purpose of ['profile','chat']){
  const d=deps();let began=false;
  d.rpc=async(_,action)=>{began=action==='begin'||began;return{id,path:'a/image.jpg',state:'pending'};};
  const invalid=request(undefined,purpose);
  invalid.headers.set('x-upload-key',`${purpose}-media-1234567890abcdef1234567890abcdef`);
  const refused=await createMediaHandler(d)(invalid);
  assert(refused.status===400);assert((await refused.json()).error==='invalid_input');assert(!began);
  assert((await createMediaHandler(d)(request(undefined,purpose))).status===200);assert(began);
 }
});
Deno.test('valid image is sanitized before storage and finalized after storage',async()=>{
 const d=deps();const trace:string[]=[];d.rpc=async(_,action)=>{trace.push(action);return{id,path:'a/image.jpg',state:'pending'};};
 d.sanitize=()=>{trace.push('sanitize');return{bytes:new Uint8Array([1,2]),width:2,height:2};};d.store=async(_,bytes)=>{trace.push('store');assert(bytes[0]===1);};
 const r=await createMediaHandler(d)(request());assert(r.status===200);assert(trace.join(',')==='begin,sanitize,store,complete');
});
Deno.test('ready upload retry skips binary write',async()=>{
 const d=deps();d.rpc=async()=>({id,path:'p',state:'ready'});d.store=async()=>{throw Error('must_not_write');};
 assert((await createMediaHandler(d)(request())).status===200);
});
Deno.test('wrong magic and oversized body are rejected',async()=>{
 const h=createMediaHandler(deps());assert((await h(request(new Uint8Array([1,2,3,4])))).status===400);
 assert((await h(request(new Uint8Array(4*1024*1024+1)))).status===413);
});
Deno.test('storage error never finalizes metadata or exposes provider details',async()=>{
 const d=deps();let complete=false;d.rpc=async(_,action)=>{complete=action==='complete';return{id,path:'p',state:'pending'};};
 d.store=async()=>{throw Error('secret-provider-detail');};const r=await createMediaHandler(d)(request());
 assert(r.status===503);assert(!complete);assert(!(await r.text()).includes('secret-provider-detail'));
});

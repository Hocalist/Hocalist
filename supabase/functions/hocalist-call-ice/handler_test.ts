import {createCallIceHandler,createCallIceBrowserHandler} from './handler.ts';
function assert(value:unknown){if(!value)throw Error('assertion failed');}
const id='90000000-0000-4000-8000-000000000001';
const request=(body=JSON.stringify({call_id:id}))=>new Request('https://example.test',{method:'POST',headers:{authorization:'Bearer synthetic'},body});
function deps(){return {enabled:true,secret:'synthetic-test-only',urls:['turn:relay.example.test:3478?transport=udp'],authenticate:async()=>id,callState:async()=>'accepted',now:()=>1000000};}
Deno.test('localhost preflight is bounded and never authenticates or issues credentials',async()=>{
 let calls=0;
 const handler=createCallIceBrowserHandler({...deps(),authenticate:async()=>{calls++;return id;}});
 const allowed=await handler(new Request('https://example.test',{method:'OPTIONS',headers:{Origin:'http://127.0.0.1:7359'}}));
 assert(allowed.status===204&&allowed.headers.get('Access-Control-Allow-Origin')==='http://127.0.0.1:7359');
 assert(await allowed.text()===''&&calls===0);
 const denied=await handler(new Request('https://example.test',{method:'OPTIONS',headers:{Origin:'https://outsider.example'}}));
 assert(denied.status===403&&!denied.headers.has('Access-Control-Allow-Origin')&&calls===0);
});
Deno.test('browser errors retain exact localhost CORS without bypassing auth or activation',async()=>{
 const req=()=>new Request('https://example.test',{method:'POST',headers:{Origin:'http://127.0.0.1:7359',authorization:'Bearer synthetic'},body:JSON.stringify({call_id:id})});
 const disabled=await createCallIceBrowserHandler({...deps(),enabled:false})(req());
 assert(disabled.status===404&&disabled.headers.get('Access-Control-Allow-Origin')==='http://127.0.0.1:7359');
 const signedOut=await createCallIceBrowserHandler({...deps(),authenticate:async()=>null})(req());
 assert(signedOut.status===401&&signedOut.headers.get('cache-control')==='no-store');
});
Deno.test('disabled infrastructure and signed-out users receive no relay credentials',async()=>{
 const d=deps();let calls=0;d.callState=async()=>{calls++;return 'accepted';};
 assert((await createCallIceHandler({...d,enabled:false})(request())).status===404);
 assert((await createCallIceHandler({...d,authenticate:async()=>null})(request())).status===401);assert(calls===0);
});
Deno.test('ended calls including admin-disabled calls cannot obtain credentials',async()=>{
 for(const state of ['ended','ringing','missed'])assert((await createCallIceHandler({...deps(),callState:async()=>state})(request())).status===409);
});
Deno.test('credential has bounded lifetime, is not shared secret and response cannot cache',async()=>{
 const r=await createCallIceHandler(deps())(request());const b=await r.json();
 assert(r.status===200&&r.headers.get('cache-control')==='no-store');assert(b.expires_at===1600);
 assert(b.iceServers[0].username===`1600:${id}`);assert(b.iceServers[0].credential!==deps().secret);
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(deps().secret),{name:'HMAC',hash:'SHA-1'},false,['verify']);
 const signature=Uint8Array.from(atob(b.iceServers[0].credential),c=>c.charCodeAt(0));
 assert(await crypto.subtle.verify('HMAC',key,signature,new TextEncoder().encode(b.iceServers[0].username)));
});
Deno.test('oversized and malformed input never reaches the call lookup',async()=>{
 let calls=0;const d={...deps(),callState:async()=>{calls++;return 'accepted';}};
 assert((await createCallIceHandler(d)(request('x'.repeat(4097)))).status===413);
 assert((await createCallIceHandler(d)(request('{}'))).status===400);assert(calls===0);
});

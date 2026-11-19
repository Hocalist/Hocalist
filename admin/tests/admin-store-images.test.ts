import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleEvidenceCore,type CoreRequest} from '../app/lib/admin-http';
import {storeImageResolver} from '../app/lib/admin-media-evidence';
const id='90000000-0000-4000-8000-000000000001';
const token=`header.${Buffer.from(JSON.stringify({sub:id,exp:9999999999,aal:'aal2'})).toString('base64url')}.signature`;
const req:CoreRequest={method:'POST',origin:'https://admin.hocalist.com',host:'admin.hocalist.com',secFetchSite:'same-origin',sessionToken:token,refreshToken:null,pendingToken:null,nextPath:null,body:{submission_id:id,media_id:id}};
const config={url:'https://project.supabase.co',anonKey:'test-public'};
test('Store photo requires exact admin listing reference before bytes',async()=>{
 const calls:string[]=[];
 const fetchImpl=(async(input,init)=>{const url=String(input);calls.push(url);
 assert.equal(new Headers(init?.headers).get('Authorization'),`Bearer ${token}`);
 if(url.includes('/rpc/admin_store_image_reference'))return Response.json({reference_ok:true});
 assert.equal(new URL(url).searchParams.get('action'),'store-evidence');
 return new Response(new Uint8Array([255,216,255,217]),{headers:{'Content-Type':'image/jpeg'}});
 }) as typeof fetch;
 const result=await handleEvidenceCore(req,{config,isProduction:false,mfaPolicy:'off',evidenceHost:null,fetchImpl},storeImageResolver,'store');
 assert.equal(result.status,200);assert.equal(calls.length,2);
});
test('Store denied reference and cross-site request never read photos',async()=>{
 let calls=0;const fetchImpl=(async()=>{calls++;return Response.json({reference_ok:false})}) as typeof fetch;
 const deps={config,isProduction:false,mfaPolicy:'off' as const,evidenceHost:null,fetchImpl};
 assert.equal((await handleEvidenceCore(req,deps,storeImageResolver,'store')).status,404);assert.equal(calls,1);
 assert.equal((await handleEvidenceCore({...req,origin:'https://other.test',secFetchSite:'cross-site'},deps,storeImageResolver,'store')).status,403);assert.equal(calls,1);
});

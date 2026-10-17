import {test} from 'node:test';
import assert from 'node:assert/strict';

test('actual status route preserves server credit admission independently of subscription',async()=>{
 const headersPath=require.resolve('next/headers');
 require(headersPath);
 const headersModule=require.cache[headersPath]!;
 const originalHeaders=headersModule.exports;
 const originalFetch=globalThis.fetch;
 const originalUrl=process.env.HOCALIST_SUPABASE_URL;
 const originalKey=process.env.HOCALIST_SUPABASE_ANON_KEY;
 try {
  headersModule.exports={cookies:async()=>({get:(name:string)=>name==='hocalist_site_session'?{value:'synthetic-session'}:undefined})};
  process.env.HOCALIST_SUPABASE_URL='https://billing-test.example';
  process.env.HOCALIST_SUPABASE_ANON_KEY='synthetic-public-key';
  const {GET}=require('../app/api/billing/status/route') as typeof import('../app/api/billing/status/route');
  for(const allowed of [true,false,undefined]){
   globalThis.fetch=async(input,init)=>{
    assert.equal(String(input),'https://billing-test.example/rest/v1/rpc/website_purchase_status');
    assert.equal((init?.headers as Record<string,string>).Authorization,'Bearer synthetic-session');
    return new Response(JSON.stringify({subscription:null,credit_purchase_allowed:allowed,options:[{id:'test-option'}]}),{status:200});
   };
   const response=await GET(new Request('http://localhost/api/billing/status'));
   assert.equal(response.status,200);
   const body=await response.json();
   assert.equal(body.credit_purchase_allowed,allowed===true);
   assert.equal(body.subscription,null);
   assert.equal(body.options.length,1);
  }
 }finally{
  headersModule.exports=originalHeaders;globalThis.fetch=originalFetch;
  if(originalUrl===undefined)delete process.env.HOCALIST_SUPABASE_URL;else process.env.HOCALIST_SUPABASE_URL=originalUrl;
  if(originalKey===undefined)delete process.env.HOCALIST_SUPABASE_ANON_KEY;else process.env.HOCALIST_SUPABASE_ANON_KEY=originalKey;
 }
});

import {strict as assert} from 'node:assert';
import Stripe from 'npm:stripe@22.6.2';
import {createHandler, account, type Receipt} from './handler.ts';
const secret='whsec_synthetic_local_test_only';
const stripe=new Stripe('sk_test_synthetic_local_test_only');
const event=(changes:Record<string,unknown>={})=>({id:'evt_synthetic1',object:'event',livemode:false,
  created:Math.floor(Date.now()/1000),type:'invoice.paid',data:{object:{id:'in_synthetic1',livemode:false}},...changes});
async function request(value:unknown, time=Math.floor(Date.now()/1000), tamper=false) {
  const payload=JSON.stringify(value);
  const header=await stripe.webhooks.generateTestHeaderStringAsync({payload,secret,timestamp:time,cryptoProvider:Stripe.createSubtleCryptoProvider()});
  return new Request('http://localhost/webhook',{method:'POST',headers:{'stripe-signature':header},body:payload+(tamper?' ':'')});
}
Deno.test('signed test event produces minimal durable receipt without customer data',async()=>{
  const receipts:Receipt[]=[];
  const handler=createHandler({signingSecret:secret,receive:async r=>{receipts.push(r);}});
  assert.equal((await handler(await request(event()))).status,200);
  assert.deepEqual(Object.keys(receipts[0]).sort(),['p_account','p_created','p_event_id','p_livemode','p_object_id','p_type']);
  assert.equal(receipts[0].p_account,account);
});
Deno.test('tampered, expired, missing signature, live and foreign account events never reach storage',async()=>{
  let calls=0;
  const handler=createHandler({signingSecret:secret,receive:async()=>{calls++;}});
  for(const req of [await request(event(),Math.floor(Date.now()/1000),true),
    await request(event(),Math.floor(Date.now()/1000)-600),await request(event({livemode:true})),
    await request(event({account:'acct_wrong'})),new Request('http://localhost',{method:'POST',body:'{}'})]) {
    assert.equal((await handler(req)).status,400);
  }
  assert.equal(calls,0);
});
Deno.test('signed deposit checkout fixture is stored as a durable receipt only',async()=>{
  const receipts:Receipt[]=[];
  const handler=createHandler({signingSecret:secret,receive:async r=>{receipts.push(r);}});
  const deposit=event({type:'checkout.session.completed',
    data:{object:{id:'cs_test_depositlocal1',livemode:false,metadata:{kind:'credit_deposit'}}}});
  assert.equal((await handler(await request(deposit))).status,200);
  assert.equal(receipts.length,1);
  assert.equal(receipts[0].p_type,'checkout.session.completed');
  assert.equal(receipts[0].p_object_id,'cs_test_depositlocal1');
  assert.equal(JSON.stringify(receipts[0]).includes('metadata'),false,'receipts never copy event payload data');
});
Deno.test('unknown event ignored, failure retried, wrong method and oversized body rejected',async()=>{
  let calls=0;
  const handler=createHandler({signingSecret:secret,receive:async()=>{calls++;throw new Error('synthetic failure');}});
  assert.equal((await handler(await request(event({type:'unhandled.event'})))).status,200);
  assert.equal(calls,0);
  assert.equal((await handler(await request(event()))).status,503);
  assert.equal((await handler(new Request('http://localhost'))).status,405);
  assert.equal((await handler(new Request('http://localhost',{method:'POST',headers:{'stripe-signature':'x'},body:'x'.repeat(262145)}))).status,413);
});

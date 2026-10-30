import {strict as assert} from 'node:assert';
import {ACCOUNT,type Backend,type ObjectMap} from '../_shared/stripe-test-billing.ts';
import {createPaygoCollectionHandler} from './handler.ts';
const CHARGE='10000000-0000-4000-8000-000000000001',TARGET='10000000-0000-4000-8000-000000000002';
class Fake{
 calls:Array<{path:string;params?:Record<string,string>;key?:string}>=[];
 rpcCalls:Array<{name:string;body:ObjectMap}>=[];
 job:ObjectMap={id:CHARGE,target_id:TARGET,phase:'initial',state:'queued',customer_id:'cus_Test',payment_method_id:'pm_Test',amount_minor:200,may_confirm:true,created_at:new Date().toISOString()};
 intent:ObjectMap={id:'pi_Test',livemode:false,customer:'cus_Test',payment_method:'pm_Test',amount:200,amount_received:0,currency:'usd',status:'requires_confirmation',metadata:{app:'hocalist',kind:'paygo_targeting',charge_id:CHARGE,target_id:TARGET,phase:'initial'}};
 outcome='succeeded';lostConfirmResponse=false;revokeBeforeConfirm=false;
 async rpc(name:string,body:ObjectMap={}){
  this.rpcCalls.push({name,body});
  if(name==='paygo_charge_context')return {...this.job,may_confirm:this.revokeBeforeConfirm&&this.job.payment_intent_id?false:this.job.may_confirm};
  if(name==='paygo_charge_bind'){this.job.payment_intent_id=body.p_intent;return null;}
  if(name==='paygo_charge_finish')return null;
  throw new Error('Unexpected RPC');
 }
 async stripe(path:string,params?:Record<string,string>,key?:string){
  this.calls.push({path,params,key});
  if(path==='account')return {id:ACCOUNT};
  if(path.endsWith('/confirm')){this.intent.status=this.outcome;this.intent.amount_received=this.outcome==='succeeded'?200:0;if(this.lostConfirmResponse)throw new Error('response lost');return this.intent;}
  if(path.endsWith('/cancel')){this.intent.status='canceled';return this.intent;}
  if(params?.payment_method&&path.startsWith('payment_intents/')){this.intent.payment_method=params.payment_method;this.intent.status='requires_confirmation';}
  return {...this.intent};
 }
 run(allowed=true,enabled=true){return createPaygoCollectionHandler(this as unknown as Backend,{enabled,authorise:()=>allowed})(new Request('https://example.com',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({charge_id:CHARGE})}));}
}
Deno.test('collection creates without charging, binds, then confirms a stable payment identity',async()=>{
 const f=new Fake();const r=await f.run();assert.equal(r.status,200);assert.deepEqual(await r.json(),{state:'succeeded'});
 const create=f.calls.find(x=>x.path==='payment_intents')!;assert.equal(create.params?.confirm,undefined);assert.equal(create.params?.amount,'200');
 assert.equal(create.key,`hocalist-paygo-create-${CHARGE}`);
 assert.equal(f.calls.find(x=>x.path.endsWith('/confirm'))?.params?.off_session,'true');
 const finish=f.rpcCalls.find(x=>x.name==='paygo_charge_finish')!;assert.equal(finish.body.p_amount,200);assert.equal(finish.body.p_state,'succeeded');
});
Deno.test('a lost confirmation response is reconciled without another payment',async()=>{
 const f=new Fake();f.lostConfirmResponse=true;assert.equal((await f.run()).status,200);
 assert.equal(f.calls.filter(x=>x.path==='payment_intents').length,1);
 assert.equal(f.rpcCalls.find(x=>x.name==='paygo_charge_finish')?.body.p_state,'succeeded');
});
Deno.test('a bound payment is retrieved on retry, never recreated',async()=>{
 const f=new Fake();f.job.payment_intent_id='pi_Test';f.intent.status='succeeded';f.intent.amount_received=200;
 assert.equal((await f.run()).status,200);assert.ok(!f.calls.some(x=>x.path==='payment_intents'||x.path.endsWith('/confirm')));
});
for(const state of ['requires_action','requires_payment_method','processing','canceled'])Deno.test(`${state} is recorded without granting paid credits`,async()=>{
 const f=new Fake();f.outcome=state;const response=await f.run();assert.equal(response.status,200);
 assert.equal(f.rpcCalls.find(x=>x.name==='paygo_charge_finish')?.body.p_state,state);
});
for(const [name,mutate]of [
 ['wrong customer',(f:Fake)=>{f.intent.customer='cus_Other';}],
 ['wrong amount',(f:Fake)=>{f.intent.amount=500;}],
 ['wrong currency',(f:Fake)=>{f.intent.currency='eur';}],
 ['live mode',(f:Fake)=>{f.intent.livemode=true;}],
 ['foreign deal',(f:Fake)=>{f.intent.metadata={...f.intent.metadata as ObjectMap,target_id:'other'};}],
 ['short successful receipt',(f:Fake)=>{f.job.payment_intent_id='pi_Test';f.intent.status='succeeded';f.intent.amount_received=199;}],
]as const)Deno.test(`${name} cannot settle a charge`,async()=>{
 const f=new Fake();mutate(f);assert.equal((await f.run()).status,503);assert.ok(!f.rpcCalls.some(x=>x.name==='paygo_charge_finish'));
});
Deno.test('revocation between preparation and confirmation cancels the uncharged intent',async()=>{
 const f=new Fake();f.revokeBeforeConfirm=true;assert.equal((await f.run()).status,200);
 assert.ok(!f.calls.some(x=>x.path.endsWith('/confirm')));assert.ok(f.calls.some(x=>x.path.endsWith('/cancel')));
});
Deno.test('old unbound jobs stop instead of reusing an expired provider retry key',async()=>{
 const f=new Fake();f.job.created_at=new Date(Date.now()-24*60*60*1000).toISOString();assert.equal((await f.run()).status,503);
 assert.ok(!f.calls.some(x=>x.path==='payment_intents'));
});
Deno.test('worker authentication and disabled gate prevent all billing access',async()=>{
 const f=new Fake();assert.equal((await f.run(false)).status,403);assert.equal((await f.run(true,false)).status,503);assert.equal(f.calls.length,0);assert.equal(f.rpcCalls.length,0);
});
Deno.test('completed jobs do not create another intent',async()=>{
 const f=new Fake();f.job.state='succeeded';assert.equal((await f.run()).status,200);assert.equal(f.calls.length,1);
});
Deno.test('returned credits can cover the complete fee without creating a card payment',async()=>{
 const f=new Fake();f.job.amount_minor=0;f.job.fee_minor=200;
 assert.equal((await f.run()).status,200);assert.ok(!f.calls.some(x=>x.path.startsWith('payment_intents')));
 const finish=f.rpcCalls.find(x=>x.name==='paygo_charge_finish')!;assert.equal(finish.body.p_amount,0);assert.equal(finish.body.p_intent,null);
});
Deno.test('an explicit retry updates the card on the same intent and uses its own retry key',async()=>{
 const f=new Fake();f.job.payment_intent_id='pi_Test';f.job.retry_generation=1;f.job.state='pending';f.job.payment_method_id='pm_Replacement';f.intent.status='requires_payment_method';
 assert.equal((await f.run()).status,200);assert.ok(!f.calls.some(x=>x.path==='payment_intents'));
 assert.equal(f.calls.find(x=>x.path==='payment_intents/pi_Test'&&x.params)?.params?.payment_method,'pm_Replacement');
 assert.equal(f.calls.find(x=>x.path.endsWith('/confirm'))?.key,`hocalist-paygo-confirm-${CHARGE}-1`);
});
for(const [name,method,expected] of [['matching','pm_Test',200],['foreign','pm_Other',503],['absent',null,503]] as const)Deno.test(`a cleared declined card with ${name} error identity is checked`,async()=>{
 const f=new Fake();f.job.payment_intent_id='pi_Test';f.intent.status='requires_payment_method';f.intent.payment_method=null;
 f.intent.last_payment_error={payment_method:method?{id:method}:null};
 const r=await f.run();assert.equal(r.status,expected);
 assert.equal(f.rpcCalls.some(x=>x.name==='paygo_charge_finish'),expected===200);
 if(expected===200)assert.equal(f.rpcCalls.find(x=>x.name==='paygo_charge_finish')?.body.p_state,'requires_payment_method');
 assert.ok(!f.calls.some(x=>x.path==='payment_intents'||x.path.endsWith('/confirm')));
});

import {strict as assert} from 'node:assert';
import {ACCOUNT,type Backend,BillingError,type ObjectMap} from '../_shared/stripe-test-billing.ts';
import {createPaygoRecoveryHandler} from './handler.ts';
const CHARGE='10000000-0000-4000-8000-000000000001',USER='10000000-0000-4000-8000-000000000002';
class Fake{
 calls:string[]=[];deny=false;
 job:ObjectMap={id:CHARGE,state:'requires_action',payment_intent_id:'pi_Test',customer_id:'cus_Test',payment_method_id:'pm_Test',amount_minor:200,target_id:USER,phase:'initial'};
 intent:ObjectMap={id:'pi_Test',status:'requires_action',livemode:false,customer:'cus_Test',amount:200,currency:'usd',client_secret:'pi_Test_secret_Synthetic',metadata:{app:'hocalist',kind:'paygo_targeting',charge_id:CHARGE,target_id:USER,phase:'initial'}};
 async user(){return USER;}
 async rpc(name:string,body:ObjectMap={}){this.calls.push(name);if(name==='paygo_charge_for_user'){assert.equal(body.p_user,USER);if(this.deny)throw new BillingError('billing_access_denied',403);return this.job;}throw new Error('Unexpected RPC');}
 async stripe(path:string){this.calls.push(path);if(path==='account')return {id:ACCOUNT};return this.intent;}
 run(operation='verify'){return createPaygoRecoveryHandler(this as unknown as Backend,{enabled:true,publishableKey:'pk_test_Synthetic'})(new Request('https://example.com',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation,charge_id:CHARGE})}));}
}
Deno.test('only an authenticated charge owner can receive bank-verification capability',async()=>{
 const f=new Fake();const r=await f.run();assert.equal(r.status,200);assert.match(r.headers.get('Cache-Control')??'',/no-store/);
 assert.deepEqual(await r.json(),{state:'requires_action',client_secret:'pi_Test_secret_Synthetic',publishable_key:'pk_test_Synthetic'});
 f.deny=true;assert.equal((await f.run()).status,403);
});
for(const [label,change]of [
 ['customer mismatch',(f:Fake)=>{f.intent.customer='cus_Other';}],
 ['amount mismatch',(f:Fake)=>{f.intent.amount=201;}],
 ['live mode',(f:Fake)=>{f.intent.livemode=true;}],
 ['other deal',(f:Fake)=>{f.intent.metadata={...f.intent.metadata as ObjectMap,target_id:'other'};}],
 ['invalid secret',(f:Fake)=>{f.intent.client_secret='another_secret';}],
]as const)Deno.test(`${label} cannot reveal a client secret`,async()=>{
 const f=new Fake();change(f);const r=await f.run();assert.equal(r.status,503);assert.ok(!JSON.stringify(await r.json()).includes('secret_'));
});
Deno.test('a completed provider result requests server refresh instead of trusting stale UI',async()=>{
 const f=new Fake();f.intent.status='succeeded';assert.deepEqual(await(await f.run()).json(),{state:'needs_refresh'});
});
Deno.test('refreshing a queued job cannot create a payment from the browser',async()=>{
 const f=new Fake();f.job.state='queued';f.job.payment_intent_id=null;
 assert.deepEqual(await(await f.run('refresh')).json(),{state:'queued'});assert.ok(!f.calls.some(x=>x==='payment_intents'));
});

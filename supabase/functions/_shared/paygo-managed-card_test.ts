import {strict as assert} from 'node:assert';
import {type Backend,type ObjectMap} from './stripe-test-billing.ts';
import {refreshManagedPaygoCard} from './paygo-managed-card.ts';
class Fake {
 context:ObjectMap|null={customer_id:'cus_Test',payment_method_id:'pm_Old'};
 customer:ObjectMap={id:'cus_Test',livemode:false,invoice_settings:{default_payment_method:'pm_New'}};
 method:ObjectMap={id:'pm_New',customer:'cus_Test',type:'card',livemode:false};
 calls:string[]=[];updated:ObjectMap|null=null;
 async rpc(name:string,body:ObjectMap){this.calls.push(name);assert.equal(body.p_user,'synthetic-owner');if(name==='paygo_card_context')return this.context;if(name==='paygo_card_refresh'){this.updated=body;return null;}throw new Error('Unexpected RPC');}
 async stripe(path:string){this.calls.push(path);if(path.startsWith('customers/'))return this.customer;if(path.startsWith('payment_methods/'))return this.method;throw new Error('Unexpected provider call');}
 run(){return refreshManagedPaygoCard(this as unknown as Backend,'synthetic-owner');}
}
Deno.test('managed card refresh uses the verified customer default without charging',async()=>{
 const f=new Fake();await f.run();assert.deepEqual(f.updated,{p_user:'synthetic-owner',p_customer:'cus_Test',p_previous:'pm_Old',p_method:'pm_New'});assert.ok(!f.calls.some(call=>call.includes('payment_intents')));
});
Deno.test('no existing consent means no provider access or permission creation',async()=>{const f=new Fake();f.context=null;await f.run();assert.deepEqual(f.calls,['paygo_card_context']);});
for(const [name,change] of [
 ['foreign customer',(f:Fake)=>{f.customer.id='cus_Other';}],
 ['live customer',(f:Fake)=>{f.customer.livemode=true;}],
 ['foreign card',(f:Fake)=>{f.method.customer='cus_Other';}],
 ['live card',(f:Fake)=>{f.method.livemode=true;}],
 ['non-card',(f:Fake)=>{f.method.type='bank_account';}],
] as const)Deno.test(`managed refresh refuses ${name}`,async()=>{const f=new Fake();change(f);await assert.rejects(f.run(),/review_required/);assert.equal(f.updated,null);});

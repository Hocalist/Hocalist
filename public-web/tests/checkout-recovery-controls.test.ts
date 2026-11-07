import {test} from 'node:test';
import assert from 'node:assert/strict';
import {closeUnpaidCheckout} from '../app/billing/close-unpaid-checkout';
import {type CheckoutRow,type CheckoutIntent,readIntent,writeIntent,shouldClearIntent} from '../app/lib/website-checkout';
const intent:CheckoutIntent={kind:'credit_deposit',value:'pack',key:'retry-key',checkoutId:null};
const checkout:CheckoutRow={id:'checkout',kind:'credit_deposit',state:'open',amount_minor:2000,option_id:'pack'};
test('closing an unpaid checkout requires provider confirmation for the exact checkout', async t => {
 const send=t.mock.method(globalThis,'fetch',async()=>Response.json({cancelled:true,checkoutId:'other'}));
 await assert.rejects(closeUnpaidCheckout('checkout'),/confirm/);
 send.mock.mockImplementation(async()=>Response.json({cancelled:true,checkoutId:'checkout'}));
 await closeUnpaidCheckout('checkout');
 assert.deepEqual(JSON.parse(String(send.mock.calls[1].arguments[1]?.body)),{kind:'cancel',checkoutId:'checkout'});
});
test('recovery remains per account and completion must match exact checkout',()=>{
 const items=new Map<string,string>();const storage={getItem:(k:string)=>items.get(k)??null,setItem:(k:string,v:string)=>{items.set(k,v);},removeItem:(k:string)=>{items.delete(k);}};
 writeIntent(storage,'seller-a',{...intent,checkoutId:'checkout'});
 assert.equal(readIntent(storage,'seller-b'),null);
 assert.equal(shouldClearIntent(readIntent(storage,'seller-a'),{...checkout,id:'other',state:'expired'}),false);
 assert.equal(shouldClearIntent(readIntent(storage,'seller-a'),{...checkout,state:'expired'}),true);
});

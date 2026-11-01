import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import CheckoutRecovery from '../app/billing/CheckoutRecovery';
import {type CheckoutRow,type CheckoutIntent,readIntent,writeIntent,shouldClearIntent} from '../app/lib/website-checkout';
const intent:CheckoutIntent={kind:'credit_deposit',value:'pack',key:'retry-key',checkoutId:null};
const checkout:CheckoutRow={id:'checkout',kind:'credit_deposit',state:'open',amount_minor:2000,option_id:'pack'};
const render=(row:CheckoutRow|null,saved:CheckoutIntent|null,busy=false)=>renderToStaticMarkup(createElement(CheckoutRecovery,{checkout:row,retained:saved,busy,onContinue:()=>{},onCancel:()=>{}}));
test('lost checkout response still exposes resume without unsafe cancellation',()=>{
 const html=render(null,intent);assert.match(html,/Continue previous checkout/);assert.doesNotMatch(html,/Cancel unpaid checkout/);
 assert.equal(shouldClearIntent(intent,null),false);
});
test('known open purchase exposes both actions, creating state cannot cancel',()=>{
 assert.match(render(checkout,null),/Cancel unpaid checkout/);
 assert.doesNotMatch(render({...checkout,state:'creating'},intent),/Cancel unpaid checkout/);
 assert.equal((render(checkout,intent,true).match(/disabled=""/g)||[]).length,2);
 assert.equal(render(null,null),'');
});
test('recovery remains per account and completion must match exact checkout',()=>{
 const items=new Map<string,string>();const storage={getItem:(k:string)=>items.get(k)??null,setItem:(k:string,v:string)=>{items.set(k,v);},removeItem:(k:string)=>{items.delete(k);}};
 writeIntent(storage,'seller-a',{...intent,checkoutId:'checkout'});
 assert.equal(readIntent(storage,'seller-b'),null);
 assert.equal(shouldClearIntent(readIntent(storage,'seller-a'),{...checkout,id:'other',state:'expired'}),false);
 assert.equal(shouldClearIntent(readIntent(storage,'seller-a'),{...checkout,state:'expired'}),true);
});

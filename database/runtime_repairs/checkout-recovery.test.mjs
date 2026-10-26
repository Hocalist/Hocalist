import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,MB,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('pending checkouts are owner-scoped and provider recovery context is service-only',async()=>{
 const db=await setup(false);
 try {
 for(const path of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','../commercial/090_credit_batches.sql','../commercial/091_buyer_rewards.sql','../commercial/092_credit_settlement.sql','../commercial/094_deposit_checkout.sql','../website_completion/172_website_purchase_status.sql','./194_credit_subscription.sql','./206_credit_access.sql','./226_checkout_recovery.sql'])await db.exec(await read(path));
 await db.query("INSERT INTO hocalist.stripe_test_plans(code,price_id,amount_minor,currency,enabled) VALUES('pro','price_test_pro',1500,'usd',true) ON CONFLICT(code) DO UPDATE SET price_id=excluded.price_id,enabled=true");
 const checkout=(await db.query("SELECT hocalist.stripe_test_checkout_begin($1,'pro','00000000-0000-4000-8000-000000000077') AS d",[B])).rows[0].d;
 const own=(await callAs(db,'authenticated',B,'SELECT hocalist.website_purchase_status() AS d'))[0].d;
 assert.equal(own.selected.id,checkout.checkout_id); assert.equal(own.selected.kind,'subscription');
 assert.equal(own.selected.request_key,undefined); assert.equal(own.selected.session_id,undefined);
 const foreign=(await callAs(db,'authenticated',B,'SELECT hocalist.website_purchase_status($1) AS d',['00000000-0000-4000-8000-000000000099']))[0].d;
 assert.equal(foreign.selected,null);
 await assert.rejects(callAs(db,'authenticated',B,'SELECT hocalist.stripe_test_pending_checkout($1)',[B]),/permission denied/);
 await assert.rejects(callAs(db,'anon',null,'SELECT hocalist.stripe_test_pending_checkout($1)',[B]),/permission denied/);
 const pending=(await callAs(db,'service_role',null,'SELECT hocalist.stripe_test_pending_checkout($1) AS d',[B]))[0].d;
 assert.equal(pending.checkout_id,checkout.checkout_id);
 await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE id=$1",[MB]);
 await assert.rejects(callAs(db,'service_role',null,'SELECT hocalist.stripe_test_pending_checkout($1)',[B]),/billing_access_denied/);
 }finally{await db.close();}
});

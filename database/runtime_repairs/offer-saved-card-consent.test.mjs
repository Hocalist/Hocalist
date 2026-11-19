import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';

test('explicit saved-card authorization is seller-bound, retry-safe, and cannot replay after revocation',async()=>{
 const db=await createCommercialDb();
 try{
  for(const name of ['235_paygo_payment_setup','276_offer_saved_card_consent']){
   await db.exec(await readFile(new URL('./'+name+'.sql',import.meta.url),'utf8'));
  }
  await db.query("INSERT INTO hocalist.stripe_test_customers(membership_id,customer_id) VALUES($1,'cus_Offer')",[IDS.sellerMembership]);
  const key=crypto.randomUUID();
  const sql='SELECT hocalist.paygo_authorize_saved_card($1,$2,$3,$4,$5)';
  const args=[IDS.seller,key,'cus_Offer','pm_Card','paygo-v1'];
  await assert.rejects(callAs(db,'authenticated',IDS.seller,sql,args),/permission denied/);
  await assert.rejects(callAs(db,'service_role',null,sql,[...args.slice(0,4),'']),/invalid_authorization/);
  await assert.rejects(callAs(db,'service_role',null,sql,[IDS.seller2,...args.slice(1)]),/invalid_authorization/);
  await callAs(db,'service_role',null,sql,args);
  await callAs(db,'service_role',null,sql,args);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.paygo_payment_setups')).rows[0].n,1);
  await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.paygo_payment_revoke()');
  await assert.rejects(callAs(db,'service_role',null,sql,args),/authorization_changed/);
 }finally{await db.close();}
});

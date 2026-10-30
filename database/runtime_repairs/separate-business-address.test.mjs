import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,callAs} from '../outcomes/tests/fixture.mjs';
test('private business addresses persist independently from home with revision and identity guards',async()=>{
 const db=await setup(false);
 try {
  await db.query("INSERT INTO hocalist.profile_contacts(user_id,address_line1) VALUES($1,'Existing business') ON CONFLICT(user_id) DO UPDATE SET address_line1='Existing business'",[B]);
  await db.exec(await readFile(new URL('../../supabase/migrations/20261026093527_separate_saved_business_address.sql',import.meta.url),'utf8'));
  const read=async(u)=>(await callAs(db,'authenticated',u,'SELECT hocalist.business_address() AS d'))[0].d;
  const save=async(u,input,key)=>(await callAs(db,'authenticated',u,'SELECT hocalist.business_address($1::jsonb,$2) AS d',[JSON.stringify(input),key]))[0].d;
  const first=await read(B);assert.equal(first.address_line1,'Existing business');
  const input={expected_revision:first.revision,address_line1:'20 Business Street',city:'Chicago',region:'IL',country_code:'US'};
  const changed=await save(B,input,'business-test');
  assert.equal(changed.address_line1,'20 Business Street');
  assert.equal((await save(B,input,'business-test')).revision,changed.revision);
  assert.equal((await read(B)).city,'Chicago');
  assert.equal((await db.query('SELECT address_line1 FROM hocalist.profile_contacts WHERE user_id=$1',[B])).rows[0].address_line1,'Existing business');
  await assert.rejects(save(B,{...input,address_line1:'Other'},'business-test'),/idempotency_conflict/);
  await assert.rejects(save(B,input,'stale'),/revision_conflict/);
  await assert.rejects(read(A),/access_denied/);
  assert.notEqual((await read(C)).address_line1,'20 Business Street');
  await assert.rejects(callAs(db,'authenticated',B,'SELECT * FROM hocalist.seller_business_addresses'),/permission denied/);
  await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1",[B]);
  await assert.rejects(read(B),/access_denied/);
 }finally{await db.close();}
});

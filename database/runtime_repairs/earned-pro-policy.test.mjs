import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,callAs,IDS} from '../commercial_completion/tests/fixture.mjs';
test('approved policy keeps paid plans authoritative and exposes following-month calendar configuration',async()=>{
 const db=await createCommercialDb();
 try {
  await db.exec(await readFile(new URL('./229_earned_pro_policy.sql',import.meta.url),'utf8'));
  const p=(await db.query('SELECT * FROM hocalist.entitlement_policy')).rows[0];
  assert.equal(p.earned_pro_threshold,7);assert.equal(p.calendar_timezone,'UTC');assert.equal(p.paid_overlap,'paid_priority');
  assert.equal(p.annual_enabled,true);assert.equal(p.trial_days,14);
  const result=await callAs(db,'authenticated',IDS.seller,'SELECT hocalist.account_entitlement() AS data');
  assert.equal(result[0].data.effective_plan,'free');
  assert.equal(result[0].data.policy.calendar_configured,true);
 }finally{await db.close();}
});

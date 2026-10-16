import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {setup,A,callAs} from '../outcomes/tests/fixture.mjs';
const sql=async name=>readFile(new URL('./rollout/'+name+'.sql',import.meta.url),'utf8');
test('remaining module rollout is atomic, repeat-safe and verifies privilege drift',async()=>{
 const db=await setup(false);try{
  await db.exec(await sql('preflight'));await db.exec(await sql('apply'));await db.exec(await sql('verify'));
  assert.equal((await db.query('SELECT enabled FROM hocalist.call_settings')).rows[0].enabled,false);
  await assert.rejects(db.exec(await sql('apply')),/Already installed/);await db.exec('ROLLBACK');
  await db.exec('GRANT TRUNCATE ON hocalist.buyer_rewards TO authenticated');
  await assert.rejects(db.exec(await sql('verify')),/Unexpected table privilege/);await db.exec('ROLLBACK');
  await db.exec('REVOKE TRUNCATE ON hocalist.buyer_rewards FROM authenticated');
  await db.exec('GRANT EXECUTE ON FUNCTION hocalist.reward_accrue_internal(uuid,uuid,bigint,text) TO service_role');
  await assert.rejects(db.exec(await sql('verify')),/Function privilege drift|Unexpected function ACL/);await db.exec('ROLLBACK');
  await db.exec('REVOKE EXECUTE ON FUNCTION hocalist.reward_accrue_internal(uuid,uuid,bigint,text) FROM service_role');
  await db.exec('ALTER TABLE hocalist.meetings DISABLE TRIGGER sale_final_meeting');
  await assert.rejects(db.exec(await sql('verify')),/Trigger drift/);await db.exec('ROLLBACK');
  await db.exec('ALTER TABLE hocalist.meetings ENABLE TRIGGER sale_final_meeting');
  await db.exec(await sql('verify'));await db.exec(await sql('containment'));await db.exec(await sql('containment'));
  await assert.rejects(callAs(db,'authenticated',A,'SELECT hocalist.reward_wallet()'),/permission denied/);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM hocalist.memberships")).rows[0].n,3);
 }finally{await db.close();}
});

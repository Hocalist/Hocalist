import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyAccountDrafts} from '../../tests/fixture.mjs';
const A='00000000-0000-4000-8000-000000000001', B='00000000-0000-4000-8000-000000000002';
test('important phone alerts retain the full inbox',async t=>{
 const db=await createDisposableDb();try{
 await applySignupSeed(db);await applyAccountDrafts(db);
 await db.exec(await readFile(new URL('../../drafts/007_push_delivery.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../030_notification_inbox.sql',import.meta.url),'utf8'));
 await db.exec(`INSERT INTO auth.users(id,raw_user_meta_data) VALUES('${A}','{}'),('${B}','{}');
 INSERT INTO hocalist.memberships(user_id,role,status) VALUES('${A}','buyer','active'),('${B}','buyer','active');
 INSERT INTO hocalist.push_devices(id,user_id,installation_secret_hash,token,platform,enabled,updated_at)
 SELECT gen_random_uuid(),'${A}','synthetic-hash','synthetic-device-token-'||n,'android',n<>2,
 CASE WHEN n=3 THEN now()-interval '31 days' ELSE now() END FROM generate_series(1,3) n;
 INSERT INTO hocalist.push_devices(id,user_id,installation_secret_hash,token,platform,enabled)
 VALUES(gen_random_uuid(),'${B}','synthetic-hash','synthetic-other-device-token','android',true);`);
 const emit=async(event)=> (await db.query("SELECT hocalist.notification_emit($1,$2,'new_offer',$2,'New offer','Open Hocalist','hocalist://offers','{}') id",[A,event])).rows[0].id;
 const old='10000000-0000-4000-8000-000000000001'; await emit(old);
 await db.exec(await readFile(new URL('../032_push_queue_bridge.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../runtime_repairs/223_important_push_events.sql',import.meta.url),'utf8'));
 const count=async()=> (await db.query('SELECT count(*)::int n FROM hocalist.push_deliveries')).rows[0].n;
 await t.test('no historical backfill',async()=>assert.equal(await count(),0));
 const event='10000000-0000-4000-8000-000000000002';
 await t.test('only recent enabled recipient device queues; replay dedupes',async()=>{
  await emit(event);await emit(event);assert.equal(await count(),1);
  const row=(await db.query('SELECT d.user_id FROM hocalist.push_deliveries q JOIN hocalist.push_devices d ON d.id=q.device_id')).rows[0];assert.equal(row.user_id,A);
 });
 await t.test('messages and meeting events queue, routine events stay in history',async()=>{
  const initial=await count();
  for(const kind of ['new_message','meeting_update','account_update','billing_update']) {
   await db.query("SELECT hocalist.notification_emit($1,gen_random_uuid(),$2,$1,'Synthetic event','Open Hocalist','hocalist://account','{}')",[A,kind]);
  }
  assert.equal(await count(),initial+2);
  const rows=(await db.query("SELECT kind FROM hocalist.notifications WHERE kind IN ('account_update','billing_update') ORDER BY kind")).rows;
  assert.deepEqual(rows.map(r=>r.kind),['account_update','billing_update']);
 });
 await t.test('optional preferences suppress inbox and queue',async()=>{
  await db.query('INSERT INTO hocalist.notification_preferences(user_id,offers) VALUES($1,false)',[A]);
  assert.equal(await emit('10000000-0000-4000-8000-000000000003'),null);assert.equal(await count(),3);
 });
 await t.test('restriction prevents new deliveries',async()=>{
  await db.query('UPDATE hocalist.notification_preferences SET offers=true WHERE user_id=$1',[A]);
  await db.query("UPDATE hocalist.memberships SET status='restricted' WHERE user_id=$1",[A]);
  await emit('10000000-0000-4000-8000-000000000004');assert.equal(await count(),3);
 });
 await t.test('clients cannot insert queue rows or execute helper',async()=>{
  await db.exec('SET ROLE authenticated');try {
   await assert.rejects(db.query('SELECT * FROM hocalist.push_deliveries'),{code:'42501'});
   await assert.rejects(db.query('SELECT hocalist.notification_queue_insert()'),{code:'42501'});
  }finally{await db.exec('RESET ROLE');}
 });
 }finally{await db.close();}
});

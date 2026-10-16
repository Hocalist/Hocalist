import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyAccountDrafts} from '../../tests/fixture.mjs';
const A='00000000-0000-4000-8000-000000000001', B='00000000-0000-4000-8000-000000000002';
test('desired-state saved commands',async t=>{
 const db=await createDisposableDb();try{
 await applySignupSeed(db);await applyAccountDrafts(db);
 for(const path of ['../../chat/010_chat_foundation.sql','../020_marketplace_foundation.sql','../022_saved_state.sql'])
  await db.exec(await readFile(new URL(path,import.meta.url),'utf8'));
 await db.exec(`INSERT INTO auth.users(id,raw_user_meta_data) VALUES('${A}','{}'),('${B}','{}');
 INSERT INTO hocalist.memberships(user_id,role,status) VALUES('${A}','buyer','active'),('${B}','buyer','active');`);
 const as=async(user,sql,args=[])=>{
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('SET ROLE authenticated');
  try{return (await db.query(sql,args)).rows[0]?.result;}finally{await db.exec('RESET ROLE');}
 };
 const request=await as(A,"SELECT hocalist.marketplace_command('request.create','create',$1::jsonb) AS result",
  [JSON.stringify({kind:'product',title:'Saved request',description:'Test',condition:'used',quantity:1,accepts_higher_offers:false,use_home_address:true})]);
 const set=(user,saved,key)=>as(user,'SELECT hocalist.marketplace_saved_set($1,$2,$3,$4) AS result',['request',request.id,saved,key]);
 await t.test('save/retry is stable and changed intent conflicts',async()=>{
  const result=await set(A,true,'save');assert.equal(result.saved,true);
  assert.deepEqual(await set(A,true,'save'),result);
  await assert.rejects(set(A,false,'save'),{code:'P0001'});
 });
 await t.test('another buyer cannot save private request',async()=>{
  await assert.rejects(set(B,true,'forged'),{code:'42501'});
 });
 await t.test('remove twice never re-adds and is owner scoped',async()=>{
  await set(B,false,'remove-other');
  assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.saved_items')).rows[0].n,1);
  await set(A,false,'remove');await set(A,false,'remove-again');
  assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.saved_items')).rows[0].n,0);
 });
 await t.test('old save replay does not undo newer removal',async()=>{
  await set(A,true,'save');
  assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.saved_items')).rows[0].n,0);
 });
 await t.test('restricted identity denied and clients have no table access',async()=>{
  await db.exec(`UPDATE hocalist.memberships SET status='restricted' WHERE user_id='${A}'`);
  await assert.rejects(set(A,true,'restricted'),{code:'42501'});
  await assert.rejects(as(A,'SELECT * FROM hocalist.saved_items'),{code:'42501'});
  await db.exec('SET ROLE anon');try{await assert.rejects(db.query("SELECT hocalist.marketplace_saved_set('request',$1,false,'anon')",[request.id]),{code:'42501'});}finally{await db.exec('RESET ROLE');}
 });
 }finally{await db.close();}
});

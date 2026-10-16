import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyAccountDrafts,applyStripeInbox} from '../../tests/fixture.mjs';
const A='00000000-0000-4000-8000-000000000001',B='00000000-0000-4000-8000-000000000002',ADM='00000000-0000-4000-8000-000000000003';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('support cases authorization and acknowledged workflow',async t=>{
 const db=await createDisposableDb();try{
 await applySignupSeed(db);await applyStripeInbox(db);await applyAccountDrafts(db);
 for(const p of ['../../provider-rollout/apply.sql','../../chat/010_chat_foundation.sql','../../marketplace/020_marketplace_foundation.sql','../070_support_cases.sql'])await db.exec(await read(p));
 await db.exec(`INSERT INTO auth.users(id,raw_user_meta_data) VALUES('${A}','{}'),('${B}','{}'),('${ADM}','{}');INSERT INTO hocalist.memberships(user_id,role,status) VALUES('${A}','buyer','active'),('${B}','seller','restricted');INSERT INTO hocalist.platform_admins(user_id) VALUES('${ADM}');`);
 const call=async(user,fn,params=[])=>{await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('SET ROLE authenticated');try{return(await db.query(`SELECT hocalist.${fn} AS data`,params)).rows[0].data;}finally{await db.exec('RESET ROLE');}};
 const cmd=(u,o,k,p)=>call(u,'support_command($1,$2,$3)',[o,k,p]);let first;
 await t.test('create acknowledged case, replay exact retry and reject changed intent',async()=>{
 const input={reason_code:'safety',body:'Please investigate this synthetic incident.'};first=await cmd(A,'create','case-one',input);assert.equal(first.status,'open');
 assert.deepEqual(await cmd(A,'create','case-one',input),first);
 await assert.rejects(cmd(A,'create','case-one',{...input,body:'A different synthetic report'}),{code:'P0001'});
 });
 await t.test('other users cannot see reports or review them',async()=>{
 assert.equal((await call(B,'support_list()')).items.length,0);
 await assert.rejects(call(B,'support_list(30,NULL,true)'),{code:'42501'});
 await assert.rejects(cmd(B,'review','forged',{case_id:first.id,expected_revision:1,status:'resolved',response:'Forged resolution'}),{code:'42501'});
 });
 await t.test('admin review uses carried revision and is visible only to reporter',async()=>{
 const ack=await cmd(ADM,'review','review-one',{case_id:first.id,expected_revision:1,status:'in_review',response:'We are reviewing your report.'});assert.equal(ack.revision,2);
 const mine=(await call(A,'support_list()')).items[0];assert.equal(mine.response,'We are reviewing your report.');assert.equal(mine.status,'in_review');
 await assert.rejects(cmd(ADM,'review','stale',{case_id:first.id,expected_revision:1,status:'resolved',response:'Stale'}),{code:'P0001'});
 });
 await t.test('restricted users retain support access; reasons are admin-managed',async()=>{
 await cmd(B,'create','appeal',{reason_code:'account',body:'Please review my access restriction.'});
 await cmd(ADM,'reason.save','retire',{code:'general',label:'General support',active:false,expected_revision:1});
 assert.equal((await call(A,'support_reasons()')).items.some(r=>r.code==='general'),false);
 await assert.rejects(cmd(A,'create','retired',{reason_code:'general',body:'Test report for retired reason'}),{code:'22023'});
 });
 await t.test('pagination, bounds and spoofed reporter rejection',async()=>{
 const page=await call(ADM,'support_list(1,NULL,true)');assert.equal(page.items.length,1);assert.ok(page.next_cursor);
 const next=await call(ADM,'support_list(1,$1,true)',[page.next_cursor]);assert.notEqual(next.items[0].id,page.items[0].id);
 await assert.rejects(call(A,'support_list(101,NULL,false)'),{code:'22023'});
 await assert.rejects(cmd(A,'create','spoof',{reason_code:'safety',body:'Synthetic incident details.',reporter_id:B}),{code:'22023'});
 });
 await t.test('table and internal helper access denied',async()=>{
 for(const role of ['anon','authenticated','service_role']){await db.exec(`SET ROLE ${role}`);try{
 await assert.rejects(db.query('SELECT * FROM hocalist.support_cases'),{code:'42501'});
 await assert.rejects(db.query('SELECT hocalist.support_assert_user()'),{code:'42501'});
 }finally{await db.exec('RESET ROLE');}}
 });
 await t.test('independent verification, immutable review events and containment',async()=>{
 await db.exec(await read('../verify.sql'));
 const events=(await db.query('SELECT revision,status FROM hocalist.support_case_events WHERE case_id=$1 ORDER BY revision',[first.id])).rows;
 assert.deepEqual(events.map(e=>e.status),['open','in_review']);
 await db.exec(await read('../containment.sql'));
 await assert.rejects(call(A,'support_list()'),{code:'42501'});
 assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.support_cases')).rows[0].n,2);
 });
 }finally{await db.close();}
});

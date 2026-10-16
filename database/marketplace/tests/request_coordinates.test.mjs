import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createDisposableDb,applySignupSeed,applyAccountDrafts,applyStripeInbox} from '../../tests/fixture.mjs';
const A='00000000-0000-4000-8000-000000000001', B='00000000-0000-4000-8000-000000000002';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('private request coordinates lifecycle',async t=>{
 const db=await createDisposableDb();try{
 await applySignupSeed(db);await applyStripeInbox(db);await applyAccountDrafts(db);
 for(const p of ['../../provider-rollout/apply.sql','../../chat/010_chat_foundation.sql','../020_marketplace_foundation.sql'])await db.exec(await read(p));
 const migration=await read('../021_request_coordinates.sql');
 await db.exec(await read('../request_coordinates_preflight.sql'));
 await db.exec(migration);
 await db.exec(await read('../request_coordinates_verify.sql'));
 await db.exec(`INSERT INTO auth.users(id,raw_user_meta_data) VALUES('${A}','{}'),('${B}','{}');
 INSERT INTO hocalist.memberships(user_id,role,status) VALUES('${A}','buyer','active'),('${B}','seller','active');`);
 const call=async(user,op,key,input)=>{
 await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('SET ROLE authenticated');
 try{return (await db.query('SELECT hocalist.marketplace_command($1,$2,$3) AS result',[op,key,input])).rows[0].result;}finally{await db.exec('RESET ROLE');}
 };
 const input={kind:'product',title:'Map test',description:'A mapped request',condition:'used',quantity:1,accepts_higher_offers:true,use_home_address:false,address_line1:'Private selected place',latitude:40.9,longitude:-73.8};
 let created;
 await t.test('create and lost-response retry preserve coordinates exactly once',async()=>{
 created=await call(A,'request.create','coordinates-create',input);
 assert.equal(created.location.latitude,40.9);assert.equal(created.location.longitude,-73.8);
 assert.deepEqual(await call(A,'request.create','coordinates-create',input),created);
 await assert.rejects(call(A,'request.create','coordinates-create',{...input,latitude:41}),{code:'P0001'});
 });
 await t.test('seller projection excludes exact position and private address',async()=>{
 await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[B]);await db.exec('SET ROLE authenticated');
 try{const result=(await db.query('SELECT hocalist.marketplace_request($1) AS result',[created.id])).rows[0].result;
 assert.doesNotMatch(JSON.stringify(result),/latitude|longitude|Private selected place/);
 }finally{await db.exec('RESET ROLE');}
 await assert.rejects(call(B,'request.update','forged',{...input,request_id:created.id,expected_revision:1}),{code:'42501'});
 });
 await t.test('reject invalid pairs, ranges, types and home-address coordinates',async()=>{
 for(const change of [{longitude:null},{latitude:91},{longitude:-181},{latitude:'40.9'},{use_home_address:true}])
 await assert.rejects(call(A,'request.create',JSON.stringify(change),{...input,...change}),{code:'22023'});
 });
 await t.test('manual address update clears old coordinates; stale edit rejected',async()=>{
 const updated=await call(A,'request.update','manual-update',{...input,request_id:created.id,expected_revision:1,latitude:null,longitude:null});
 assert.equal(updated.location.latitude,null);assert.equal(updated.location.longitude,null);assert.equal(updated.revision,2);
 await assert.rejects(call(A,'request.update','stale-update',{...input,request_id:created.id,expected_revision:1}),{code:'P0001'});
 });
 await t.test('clients cannot read table or private serialization helper directly',async()=>{
 await db.exec('SET ROLE authenticated');try{
 await assert.rejects(db.query('SELECT latitude FROM hocalist.requests'),{code:'42501'});
 await assert.rejects(db.query('SELECT hocalist.marketplace_request_json($1)',[created.id]),{code:'42501'});
 }finally{await db.exec('RESET ROLE');}
 });
 await t.test('repeat migration rejects changed baseline without mutation',async()=>{
 await assert.rejects(db.exec(migration),/baseline drift/);await db.exec('ROLLBACK');
 assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.requests')).rows[0].n,1);
 });
 }finally{await db.close();}
});

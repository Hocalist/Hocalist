import {test} from 'node:test';
import assert from 'node:assert/strict';
import {applyAdminBaseline,seedAdminIdentities,callAs,ADMIN,BUYER,SELLER,M_BUYER,M_SELLER,read} from '../admin_completion/tests/fixture.mjs';
test('workspace metrics are complete, private, deterministic and read-only',async t=>{
 const db=await applyAdminBaseline();
 try{
 await seedAdminIdentities(db);await db.exec(`CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $jwt$ SELECT current_setting('request.jwt.claims',true)::jsonb $jwt$; GRANT EXECUTE ON FUNCTION auth.jwt() TO authenticated;`);await db.exec(await read('../../runtime_repairs/219_admin_workspace_metrics.sql'));
 await db.exec(`SELECT set_config('request.jwt.claims','{"aal":"aal2"}',false)`);
 const load=async(user=ADMIN,role='authenticated')=>(await callAs(db,role,user,'SELECT hocalist.admin_workspace_metrics() AS d'))[0].d;
 await t.test('all seven UTC days and empty datasets are explicit',async()=>{const d=await load();assert.equal(d.series.length,7);assert.equal(d.timezone,'UTC');assert.deepEqual(d.recent_requests,[]);assert.equal(d.resources.users.total,4);assert.equal(d.series.reduce((n,d)=>n+d.requests+d.offers,0),0);});
 await t.test('regular users and anonymous callers are refused',async()=>{await assert.rejects(load(BUYER),/admin|forbidden|permission/i);await assert.rejects(load(ADMIN,'anon'),/permission/i);});
 await t.test('password-only admin session is refused',async()=>{await db.exec(`SELECT set_config('request.jwt.claims','{"aal":"aal1"}',false)`);await assert.rejects(load(),/admin_mfa_required/);await db.exec(`SELECT set_config('request.jwt.claims','{"aal":"aal2"}',false)`);});
 await t.test('aggregation covers all rows rather than a paginated sample',async()=>{await db.exec(`UPDATE hocalist.memberships SET status='restricted' WHERE user_id='${BUYER}'`);const d=await load();assert.equal(d.resources.users.statuses.restricted,1);assert.equal(d.resources.users.total,4);assert.deepEqual(d.queues,{listings:0,reports:0,withdrawals:0});assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.memberships')).rows[0].n,4);});
 await t.test('recent requests, UTC periods and draft exclusion use actual stored timestamps',async()=>{
 await db.exec(`INSERT INTO hocalist.requests(buyer_user_id,buyer_profile_id,kind,title,condition,status,created_at,address_line1) VALUES
 ('${BUYER}','${M_BUYER}','product','Current request','used','active',now()-interval '1 hour','Private address'),
 ('${BUYER}','${M_BUYER}','product','Prior request','used','closed',((now() AT TIME ZONE 'UTC')::date-8)::timestamp AT TIME ZONE 'UTC',null),
 ('${BUYER}','${M_BUYER}','product','Hidden draft','used','draft',now(),null)`);
 const d=await load();assert.equal(d.periods.requests_current,1);assert.equal(d.periods.requests_previous,1);assert.equal(d.recent_requests.length,2);assert.equal(d.recent_requests[0].title,'Current request');assert.equal(d.series.reduce((n,d)=>n+d.requests,0),1);assert.ok(!JSON.stringify(d).includes('Private address'));assert.ok(!JSON.stringify(d).includes('Hidden draft'));
 });
 await db.exec(await read('../../runtime_repairs/220_admin_moderation_reasons.sql'));
 await t.test('moderation reason and decision save atomically with replay/conflict protection',async()=>{
 const id=(await db.query(`INSERT INTO hocalist.store_listings(seller_user_id,seller_profile_id,kind,title,price_label) VALUES('${SELLER}','${M_SELLER}','product','Review item','$20') RETURNING id`)).rows[0].id;
 const decide=async(user,revision,reason,key)=>(await callAs(db,'authenticated',user,`SELECT hocalist.admin_moderation_decide($1,$2,'approved',$3,$4) AS d`,[id,revision,reason,key]))[0].d;
 const first=await decide(ADMIN,1,'Meets listing requirements','reason-1');assert.deepEqual(await decide(ADMIN,1,'Meets listing requirements','reason-1'),first);
 await assert.rejects(decide(ADMIN,1,'Different reason','reason-1'),/idempotency_conflict/);
 await assert.rejects(decide(ADMIN,1,'Old revision','reason-2'),/revision_conflict/);
 await assert.rejects(decide(BUYER,2,'Not permitted','reason-3'),/admin|forbidden|permission/i);
 assert.equal((await db.query('SELECT count(*)::int AS n FROM hocalist.admin_listing_decisions')).rows[0].n,1);
 const history=(await callAs(db,'authenticated',ADMIN,'SELECT hocalist.admin_moderation_history($1) AS d',[id]))[0].d;assert.equal(history[0].reason,'Meets listing requirements');
 await assert.rejects(callAs(db,'authenticated',BUYER,'SELECT hocalist.admin_moderation_history($1)',[id]),/admin|forbidden|permission/i);
 });
 }finally{await db.close();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,MA,MB,callAs,acceptedDeal,schedule,propose,respond} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('seller request context retains location and profile metadata without private fields',async t=>{
 const db=await setup(false);
 const rpc=async(sql,args=[])=>(await callAs(db,'authenticated',B,sql,args))[0].d;
 try {
  for(const p of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','./192_confirmed_meeting_coordinates.sql']) await db.exec(await read(p));
  const discovery=await read('../discovery_completion/140_discovery_leads.sql');
  await db.exec(discovery.match(/CREATE TABLE hocalist.seller_discovery_origins[\s\S]*?\n\);/)[0]);
  await db.exec(discovery.match(/CREATE FUNCTION hocalist.discovery_distance_miles\([\s\S]*?\$\$;/)[0]);
  await db.exec(discovery.match(/CREATE FUNCTION hocalist.discovery_lead_json\([\s\S]*?\$\$;/)[0]);
  await db.exec(await read('./253_seller_lead_context.sql'));
  const input={kind:'product',title:'Tablet',description:'Synthetic',condition:'used',quantity:1,use_home_address:false,city:'Chicago',latitude:41.88,longitude:-87.63};
  const request=(await callAs(db,'authenticated',A,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',['request.create','context-test',JSON.stringify(input)]))[0].d;
  await db.query('UPDATE hocalist.requests SET use_home_address=true,latitude=NULL,longitude=NULL WHERE id=$1',[request.id]);
  await db.query('UPDATE hocalist.role_profiles SET area_label=NULL,preferred_meetup_type=$1 WHERE membership_id=$2',['Public place',MA]);
  await db.query("INSERT INTO hocalist.profile_contacts(user_id,city,region,address_line1) VALUES($1,'Chicago','IL','Private street') ON CONFLICT(user_id) DO UPDATE SET city='Chicago',region='IL',address_line1='Private street'",[A]);
  await db.query('INSERT INTO hocalist.seller_discovery_origins(seller_user_id,seller_profile_id,latitude,longitude) VALUES($1,$2,41.9,-87.7)',[B,MB]);
  await t.test('home address uses saved city without fabricating distance',async()=>{
   const d=await rpc('SELECT hocalist.marketplace_request($1) AS d',[request.id]);
   assert.equal(d.area_label,'Chicago');assert.equal(d.preferred_meetup_label,'Public place');
   assert.equal(d.distance_miles,null);assert.equal(d.last_completed_item_label,null);
   for(const field of ['location','address_line1','latitude','longitude','phone']) assert.equal(field in d,false);
   assert.equal(JSON.stringify(d).includes('Private street'),false);
  });
  await t.test('custom request location wins and discovery keeps its ranked distance',async()=>{
   await db.query("UPDATE hocalist.requests SET use_home_address=false,city='Evanston',latitude=41.88,longitude=-87.63 WHERE id=$1",[request.id]);
   const d=await rpc('SELECT hocalist.marketplace_request($1) AS d',[request.id]);assert.equal(d.area_label,'Evanston');assert.ok(d.distance_miles>3 && d.distance_miles<5);
   const result=(await db.query('SELECT hocalist.discovery_lead_json($1,12.5) AS d',[request.id])).rows[0].d;
   assert.equal(result.distance_miles,12.5);assert.equal(result.preferred_meetup_label,'Public place');
  });
  await t.test('missing coordinates and blank preference stay honestly empty',async()=>{
   await db.query('UPDATE hocalist.requests SET latitude=NULL,longitude=NULL WHERE id=$1',[request.id]);
   await db.query("UPDATE hocalist.role_profiles SET preferred_meetup_type=NULL WHERE membership_id=$1",[MA]);
   const d=await rpc('SELECT hocalist.marketplace_request($1) AS d',[request.id]);
   assert.equal(d.distance_miles,null);assert.equal(d.preferred_meetup_label,null);
  });
  await t.test('confirmed purchase supplies its date without disclosing the past item while an unconfirmed request does not',async()=>{
   const deal=await acceptedDeal(db);
   const pending=(await propose(db,A,deal.conversationId,schedule(),'context-meeting'))[0].data;
   const meeting=(await respond(db,B,pending.id,true,pending.revision,'context-accept'))[0].data;
   await db.query('INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id) VALUES($1,$2,$3,$4,$5,$6)',[deal.requestId,meeting.id,deal.offerId,meeting.accepted_revision_id,A,B]);
   const d=await rpc('SELECT hocalist.marketplace_request($1) AS d',[request.id]);
   assert.match(d.last_completed_item_label,/^[A-Z][a-z]{2} \d{2}, \d{4}$/);
   assert.equal(JSON.stringify(d).includes('iPad Air, 5th gen or newer'),false);
  });
  await t.test('internal helper is not directly callable and patch is repeatable',async()=>{
   await assert.rejects(rpc('SELECT hocalist.marketplace_lead_context($1) AS d',[request.id]),/permission denied/);
   await db.exec(await read('./253_seller_lead_context.sql'));
   assert.equal((await rpc('SELECT hocalist.marketplace_request($1) AS d',[request.id])).area_label,'Evanston');
  });
 } finally {await db.close();}
});





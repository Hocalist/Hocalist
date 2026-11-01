import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,MB,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('business location is shared with profile and discovery without exposing a private address',async t=>{
 const db=await setup(false);
 try {
  const discovery=await read('../discovery_completion/140_discovery_leads.sql');
  await db.exec(discovery.match(/CREATE TABLE hocalist.seller_discovery_origins[\s\S]*?\n\);/)[0]);
  await db.exec(await read('../../supabase/migrations/20261026093527_separate_saved_business_address.sql'));
  await db.exec(await read('./254_shared_seller_location.sql'));
  const call=async(input,key)=>(await callAs(db,'authenticated',B,'SELECT hocalist.business_address($1::jsonb,$2) AS d',[input==null?null:JSON.stringify(input),key]))[0].d;
  let row=await call(null,null);
  const input={expected_revision:row.revision,address_line1:'Private business',city:'Chicago',region:'IL',latitude:41.88,longitude:-87.63};
  row=await call(input,'shared-address');
  await t.test('address save updates profile area and distance origin',async()=>{
   const p=(await db.query('SELECT area_label FROM hocalist.role_profiles WHERE membership_id=$1',[MB])).rows[0];
   const o=(await db.query('SELECT * FROM hocalist.seller_discovery_origins WHERE seller_user_id=$1',[B])).rows[0];
   assert.equal(p.area_label,'Chicago');assert.equal(o.area_label,'Chicago');assert.equal(o.latitude,41.88);
   assert.equal('address_line1' in o,false);
   assert.equal((await call(input,'shared-address')).revision,row.revision);
   await assert.rejects(call({...input,latitude:40},'shared-address'),/idempotency_conflict/);
  });
  await t.test('radius changes keep coordinates and update distance matching',async()=>{
   await db.query('UPDATE hocalist.role_profiles SET service_radius_miles=50 WHERE membership_id=$1',[MB]);
   const o=(await db.query('SELECT * FROM hocalist.seller_discovery_origins WHERE seller_user_id=$1',[B])).rows[0];
   assert.equal(o.radius_miles,50);assert.equal(o.latitude,41.88);
  });
  await t.test('changed unresolved address clears stale coordinates',async()=>{
   row=await call({expected_revision:row.revision,city:'Evanston'},'move-address');
   const o=(await db.query('SELECT * FROM hocalist.seller_discovery_origins WHERE seller_user_id=$1',[B])).rows[0];
   assert.equal(o.area_label,'Evanston');assert.equal(o.latitude,null);assert.equal(o.longitude,null);
   await assert.rejects(call({expected_revision:row.revision,latitude:91,longitude:0},'bad-coordinates'),/business_coordinates_valid/);
   await assert.rejects(call({expected_revision:row.revision,latitude:40},'partial-coordinates'),/invalid_coordinates/);
  });
  await t.test('buyer cannot access seller address',async()=>{
   await assert.rejects(callAs(db,'authenticated',A,'SELECT hocalist.business_address()'),/address_access_denied/);
   await assert.rejects(callAs(db,'authenticated',B,'SELECT * FROM hocalist.seller_business_addresses'),/permission denied/);
  });
 } finally {await db.close();}
});
test('home request accepts valid coordinates while invalid pairs still fail',async()=>{
 const db=await setup(false);
 try {
  await db.exec(await read('../marketplace/021_request_coordinates.sql'));
  await db.exec(await read('./255_request_home_coordinates.sql'));
  const input={kind:'product',title:'Home request',description:'Synthetic',condition:'used',quantity:1,use_home_address:true,latitude:41.88,longitude:-87.63};
  const create=async(value,key)=>(await callAs(db,'authenticated',A,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',['request.create',key,JSON.stringify(value)]))[0].d;
  await db.query("INSERT INTO hocalist.profile_contacts(user_id,city,region) VALUES($1,'Chicago','IL') ON CONFLICT(user_id) DO UPDATE SET city='Chicago',region='IL'",[A]);
  const r=await create(input,'home');assert.equal(r.location.latitude,41.88);assert.equal(r.location.city,'Chicago');
  await db.query("UPDATE hocalist.profile_contacts SET city='Evanston' WHERE user_id=$1",[A]);
  assert.equal((await db.query('SELECT city FROM hocalist.requests WHERE id=$1',[r.id])).rows[0].city,'Chicago');
  await assert.rejects(create({...input,latitude:91},'invalid'),/coordinates/);
  await assert.rejects(create({...input,longitude:null},'partial'),/coordinates/);
 }finally{await db.close();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {applyAdminBaseline,seedAdminIdentities,callAs,BUYER,SELLER,read} from '../admin_completion/tests/fixture.mjs';

test('market projection includes real timestamps without widening visibility',async t=>{
 const db=await applyAdminBaseline();
 try {
  await seedAdminIdentities(db);
  await db.exec("INSERT INTO hocalist.locations(country_code,label,status) VALUES('US','Synthetic active area','active'),('US','Synthetic retired area','retired');");
  await db.exec(await read('../../runtime_repairs/222_market_location_timestamps.sql'));
  for(const [role,user] of [['buyer',BUYER],['seller',SELLER]]) {
   await t.test(`${role} reads active areas and authoritative timestamps`,async()=>{
    const [{d}]=await callAs(db,'authenticated',user,'SELECT hocalist.marketplace_locations(NULL,true) d');
    assert.equal(d.items.length,1);
    assert.equal(d.items[0].label,'Synthetic active area');
    const stored=(await db.query('SELECT created_at::text,updated_at::text FROM hocalist.locations WHERE id=$1',[d.items[0].id])).rows[0];
    assert.equal(Date.parse(d.items[0].created_at),Date.parse(stored.created_at));
    assert.equal(Date.parse(d.items[0].updated_at),Date.parse(stored.updated_at));
   });
  }
  await t.test('anonymous access remains denied',async()=>{
   await assert.rejects(callAs(db,'anon','', 'SELECT hocalist.marketplace_locations(NULL,false)'),/permission|authentication_required/);
  });
  await t.test('reapplication is safe',async()=>{
   await db.exec(await read('../../runtime_repairs/222_market_location_timestamps.sql'));
  });
 } finally { await db.close(); }
});

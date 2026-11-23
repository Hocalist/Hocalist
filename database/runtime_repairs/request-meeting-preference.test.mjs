import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');

test('request meeting preference persists safely through buyer and seller journeys',async t=>{
 const db=await setup(false);
 const rpc=async(user,sql,args)=>(await callAs(db,'authenticated',user,sql,args))[0].d;
 const command=(user,op,key,input)=>rpc(user,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify(input)]);
 try {
  await db.exec(await read('../marketplace/021_request_coordinates.sql'));
  const migration=await read('../../supabase/migrations/20261121145318_request_preferred_meeting_place.sql');
  await db.exec(migration);
  await db.exec(migration); // Safe to apply again.
  const input={kind:'product',title:'TEST meeting preference',description:'Synthetic',condition:'used',quantity:1,
    use_home_address:false,address_line1:'100 Private Test Street',city:'Chicago',region:'IL',country_code:'US',latitude:41.88,longitude:-87.63};
  const legacy=await command(A,'request.create','legacy',input);
  assert.equal(legacy.location.prefer_meet_here,false);
  const preferred=await command(A,'request.create','preferred',{...input,prefer_meet_here:true});
  await t.test('create and idempotent retry retain preference and private address',async()=>{
   assert.equal(preferred.location.prefer_meet_here,true);
   assert.equal(preferred.location.address_line1,input.address_line1);
   assert.deepEqual(await command(A,'request.create','preferred',{...input,prefer_meet_here:true}),preferred);
  });
  await t.test('seller sees useful label but no private address or exact pin',async()=>{
   const lead=await rpc(B,'SELECT hocalist.marketplace_request($1) AS d',[preferred.id]);
   assert.equal(lead.preferred_meetup_label,'Buyer’s requested location');
   assert.ok(!JSON.stringify(lead).includes(input.address_line1));
   assert.ok(!JSON.stringify(lead).includes('41.88'));
   assert.ok(!('location' in lead));
  });
  await t.test('buyer edits can unset it; older clients preserve it',async()=>{
   const preserved=await command(A,'request.update','old-edit',{...input,request_id:preferred.id,expected_revision:preferred.revision});
   assert.equal(preserved.location.prefer_meet_here,true);
   const updated=await command(A,'request.update','edit',{...input,request_id:preferred.id,expected_revision:preserved.revision,prefer_meet_here:false});
   assert.equal(updated.location.prefer_meet_here,false);
  });
  await t.test('seller cannot edit buyer preference',async()=>{
   await assert.rejects(command(B,'request.update','seller-edit',{...input,request_id:preferred.id,expected_revision:3,prefer_meet_here:true}));
  });
  await t.test('invalid preference types rejected',async()=>{
   for (const value of ['true',1,null,{}]) await assert.rejects(command(A,'request.create',`bad-${JSON.stringify(value)}`,{...input,prefer_meet_here:value}),/invalid_field: prefer_meet_here/);
  });
 } finally {await db.close();}
});

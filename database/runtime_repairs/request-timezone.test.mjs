import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('request timezone survives commands while sellers receive no exact address',async t=>{
 const db=await setup(false);
 const rpc=async(user,sql,args)=>(await callAs(db,'authenticated',user,sql,args))[0].d;
 const command=(user,op,key,input)=>rpc(user,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify(input)]);
 try{
  for(const p of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','./192_confirmed_meeting_coordinates.sql'])await db.exec(await read(p));
  const audit=await read('../audit_repairs/200_audit_reads.sql');
  await db.exec(audit.match(/DO \$metadata\$[\s\S]*?END \$metadata\$;/)[0]);
  const discovery=await read('../discovery_completion/140_discovery_leads.sql');
  await db.exec(discovery.match(/CREATE FUNCTION hocalist.discovery_lead_json\([\s\S]*?\$\$;/)[0]);
  await db.exec(await read('./request-timezone-browser.sql'));
  const input={kind:'product',title:'Timezone fixture',description:'Synthetic',condition:'used',quantity:1,use_home_address:false,address_line1:'Private synthetic street',city:'Chicago',region:'IL',country_code:'US',latitude:41.88,longitude:-87.63,location_timezone:'America/Chicago'};
  const request=await command(A,'request.create','timezone-create',input);
  await t.test('owner read and replay retain the selected timezone',async()=>{
   assert.equal(request.location.timezone_id,'America/Chicago');
   assert.deepEqual(await command(A,'request.create','timezone-create',input),request);
  });
  await t.test('seller detail and discovery disclose timezone but no private address or coordinates',async()=>{
   for(const sql of ['SELECT hocalist.marketplace_request($1) AS d','SELECT hocalist.discovery_lead_json($1) AS d']){
    const result=await rpc(B,sql,[request.id]);
    assert.equal(result.location_timezone,'America/Chicago');
    assert.equal(result.area_label,'Chicago');
    assert.equal(JSON.stringify(result).includes('Private synthetic street'),false);
    assert.equal('latitude' in result,false);assert.equal('longitude' in result,false);assert.equal('location' in result,false);
   }
  });
  await t.test('invalid zone is rejected and a changed location updates the zone',async()=>{
   await assert.rejects(command(A,'request.create','bad-zone',{...input,location_timezone:'Not/AZone'}),/location_timezone/);
   const updated=await command(A,'request.update','update-zone',{...input,request_id:request.id,expected_revision:request.revision,location_timezone:'America/New_York'});
   assert.equal(updated.location.timezone_id,'America/New_York');
  });
  await t.test('legacy input remains valid and double application retains guards',async()=>{
   const {location_timezone,...legacy}=input;
   assert.equal((await command(A,'request.create','legacy-zone',legacy)).location.timezone_id,null);
   await db.exec(await read('./210_request_location_timezone.sql'));
   await db.exec(await read('./request-timezone-verify.sql'));
  });
  await t.test('browser patch safely upgrades the reviewed timezone-only intermediate',async()=>{
   await db.exec(`DO $test$ DECLARE original text; definition text; changed text; sig text; BEGIN
    FOREACH sig IN ARRAY ARRAY['hocalist.marketplace_lead_json(uuid)','hocalist.discovery_lead_json(uuid,double precision,integer,jsonb)'] LOOP
     SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid=sig::regprocedure;
     changed:=replace(original,'CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''''),nullif(btrim(r.region),''''),rp.area_label) END','coalesce(rp.area_label, r.city, r.region)');
     EXECUTE replace(definition,original,changed);
    END LOOP;
   END $test$;`);
   await db.exec(await read('./request-timezone-browser.sql'));
   await db.exec(await read('./request-timezone-verify.sql'));
  });
 }finally{await db.close();}
});

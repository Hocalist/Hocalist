import {test} from 'node:test';
import assert from 'node:assert/strict';
import {applyAdminBaseline,seedAdminIdentities,callAs,BUYER,SELLER,OUTSIDER,read} from '../admin_completion/tests/fixture.mjs';
const C='20000000-0000-4000-8000-000000000001',G='30000000-0000-4000-8000-000000000001',O='40000000-0000-4000-8000-000000000001',O2='40000000-0000-4000-8000-000000000002';
test('category questions preserve atomic commands and enforce configured answers',async t=>{
 const db=await applyAdminBaseline();try{
 await seedAdminIdentities(db);
 await db.exec(`INSERT INTO hocalist.catalogue_categories(id,label,scope) VALUES('${C}','Test category','product');
 INSERT INTO hocalist.catalogue_option_groups(id,category_id,label,selection_mode,is_required) VALUES('${G}','${C}','Finish','single',true);
 INSERT INTO hocalist.catalogue_options(id,group_id,label) VALUES('${O}','${G}','Matte'),('${O2}','${G}','Gloss');`);
 await db.exec(await read('../../runtime_repairs/221_category_questions.sql'));
 const command=async(user,op,input,key)=>(await callAs(db,'authenticated',user,'SELECT hocalist.marketplace_command($1,$2,$3::jsonb) AS d',[op,key,JSON.stringify(input)]))[0].d;
 const request={kind:'product',title:'Test request',condition:'used',quantity:1,category_id:C,use_home_address:false,address_line1:'Synthetic test address',city:'Chicago',region:'IL',country_code:'US'};
 const answers={[G]:[O]};let r,l;
 await t.test('required selections cannot be omitted',async()=>{await assert.rejects(command(BUYER,'request.create',request,'missing'),/required_category_answers/);assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.requests')).rows[0].n,0);});
 await t.test('selected IDs and trusted labels persist in the command response',async()=>{r=await command(BUYER,'request.create',{...request,category_answers:answers},'request-1');assert.equal(r.category_answers[0].label,'Finish');assert.deepEqual(r.category_answers[0].labels,['Matte']);assert.deepEqual(r.category_answers[0].option_ids,[O]);});
 await t.test('retries replay once and changed answers conflict',async()=>{assert.deepEqual(await command(BUYER,'request.create',{...request,category_answers:answers},'request-1'),r);await assert.rejects(command(BUYER,'request.create',{...request,category_answers:{[G]:[O2]}},'request-1'),/idempotency_conflict/);assert.equal((await db.query('SELECT count(*)::int n FROM hocalist.requests')).rows[0].n,1);});
 await t.test('invalid group, choice, multiple selection and duplicates are rejected',async()=>{for(const a of [{[O]:[O]},{[G]:[C]},{[G]:[O,O2]},{[G]:[O,O]}])await assert.rejects(command(BUYER,'request.create',{...request,category_answers:a},JSON.stringify(a).slice(0,100)),/invalid_field/);});
 await t.test('request edits preserve ownership and carry new answers',async()=>{await assert.rejects(command(OUTSIDER,'request.update',{...request,request_id:r.id,expected_revision:r.revision,category_answers:answers},'foreign'),/access_denied/);const next=await command(BUYER,'request.update',{...request,request_id:r.id,expected_revision:r.revision,category_answers:{[G]:[O2]}},'edit-1');assert.deepEqual(next.category_answers[0].labels,['Gloss']);assert.equal(next.revision,r.revision+1);});
 const listing={kind:'product',title:'Test listing',category_id:C,price_label:'25',publish_intent:'draft'};
 await t.test('drafts may omit required questions but publish cannot',async()=>{l=await command(SELLER,'store.create',listing,'listing-1');await assert.rejects(command(SELLER,'store.publish',{listing_id:l.id,expected_revision:l.revision,publish:true},'publish-missing'),/required_category_answers/);});
 await t.test('store updates save answers, duplicate copies them and public projection keeps them',async()=>{l=await command(SELLER,'store.update',{...listing,listing_id:l.id,expected_revision:l.revision,category_answers:answers},'listing-edit');assert.deepEqual(l.category_answers[0].labels,['Matte']);const copy=await command(SELLER,'store.duplicate',{listing_id:l.id},'listing-copy');assert.deepEqual(copy.category_answers,l.category_answers);l=await command(SELLER,'store.publish',{listing_id:l.id,expected_revision:l.revision,publish:true},'publish-filled');await db.exec(`UPDATE hocalist.store_listings SET moderation_status='approved' WHERE id='${l.id}'`);assert.deepEqual((await db.query('SELECT hocalist.marketplace_public_listing_json($1) d',[l.id])).rows[0].d.category_answers,l.category_answers);});
 await t.test('an active listing cannot bypass required questions by switching category',async()=>{
 const c2='20000000-0000-4000-8000-000000000002',g2='30000000-0000-4000-8000-000000000002';
 await db.exec(`INSERT INTO hocalist.catalogue_categories(id,label,scope) VALUES('${c2}','Second category','product'); INSERT INTO hocalist.catalogue_option_groups(id,category_id,label,selection_mode,is_required) VALUES('${g2}','${c2}','Size','single',true);`);
 await assert.rejects(command(SELLER,'store.update',{...listing,category_id:c2,listing_id:l.id,expected_revision:l.revision,category_answers:{}},'switch-missing'),/required_category_answers/);
 });
 await t.test('retired options and direct helper access are denied',async()=>{await db.exec(`UPDATE hocalist.catalogue_options SET status='retired' WHERE id='${O}'`);await assert.rejects(command(BUYER,'request.create',{...request,category_answers:answers},'retired'),/invalid_field/);await assert.rejects(callAs(db,'authenticated',BUYER,'SELECT hocalist.catalogue_validate_answers($1,$2,true)',[C,JSON.stringify(answers)]),/permission/);});
 await t.test('migration can be reapplied without nesting wrappers',async()=>{await db.exec(await read('../../runtime_repairs/221_category_questions.sql'));});
 }finally{await db.close();}
});

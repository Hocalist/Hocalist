import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,C,callAs,schedule} from '../outcomes/tests/fixture.mjs';

test('Store publication and custom offer private-price isolation', async () => {
  const db = await setup(false);
  const category = '20000000-0000-4000-8000-000000000001';
  const rpc = async (user, sql, args=[]) =>
    (await callAs(db,'authenticated',user,'SELECT '+sql+' AS d',args))[0].d;
  const cmd = (user,op,input,key=crypto.randomUUID()) =>
    rpc(user,'hocalist.marketplace_command($1,$2,$3::jsonb)',[op,key,JSON.stringify(input)]);
  const setPlan = plan => db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES ($1,$2,'admin') ON CONFLICT(user_id) DO UPDATE SET plan_code=excluded.plan_code",[B,plan]);
  const trends = async () => (await rpc(A,'hocalist.hocatrends_trends(10)')).items;
  const items = async id => (await rpc(A,'hocalist.hocatrends_topic_sellers($1,20)',[id])).items;
  const pref = (u,id,value) => rpc(u,'hocalist.hocatrends_listing_preference($1,$2)',[id,value]);
  try {
    for (const path of ['../marketplace/021_request_coordinates.sql','../marketplace/023_multi_negotiation.sql','../outcomes/080_sale_confirmation.sql','../media/100_private_images.sql','../discovery_completion/140_discovery_leads.sql','../discovery_completion/142_reviews.sql','../support/070_support_cases.sql','../trust/120_review_workflow.sql','./221_category_questions.sql','./282_hocatrends_store_publication.sql']) {
      await db.exec(await readFile(new URL(path,import.meta.url),'utf8'));
    }
    // Earlier baseline fixtures predate the live address privacy and chat context tables.
    await db.exec(`CREATE TABLE hocalist.seller_profile_visibility_settings(user_id uuid PRIMARY KEY,show_area boolean,show_business_address boolean);
      CREATE TABLE hocalist.seller_business_addresses(user_id uuid PRIMARY KEY,latitude double precision,longitude double precision);
      ALTER TABLE hocalist.conversation_messages ADD COLUMN offer_id uuid, ADD COLUMN enquiry_id uuid;`);
    const photo = async purpose => (await db.query("INSERT INTO hocalist.media_images(owner_user_id,intent_key,purpose,state,content_hash) VALUES($1,gen_random_uuid(),$2,'ready',repeat('a',64)) RETURNING id",[B,purpose])).rows[0].id;
    const priv = await photo('offer'), pub = await photo('store');
    const storeInput = {kind:'product', category_id:category, title:'Desk lamp',price_label:'45',publish_intent:'publish',image_media_ids:[pub]};
    const approve = id => db.query("UPDATE hocalist.store_listings SET moderation_status='approved' WHERE id=$1",[id]);
    await setPlan('pro');
    const store = await cmd(B,'store.create',storeInput);
    await approve(store.id);
    assert.deepEqual(await trends(),[]);
    await assert.rejects(pref(C,store.id,true));
    await pref(B,store.id,true);
    assert.equal((await items(store.id))[0].price_label,'$45');
    assert.equal((await trends())[0].label,'Desk lamp');
    await setPlan('free');
    assert.deepEqual(await trends(),[]);
    await assert.rejects(pref(B,store.id,true),/hocatrends_not_eligible/);
    const req=await cmd(A,'request.create',{kind:'product',title:'Private buyer request',description:'Private notes',condition:'used',quantity:1,budget_minimum_minor:1000,budget_maximum_minor:50000,currency_code:'USD',use_home_address:true,category_id:category});
    const offer={request_id:req.id,price_minor:20000,currency_code:'USD',message:'Private message',image_media_ids:[priv],...schedule()};
    const listing={title:'Office chair',image_media_ids:[pub],category_answers:{}};
    const key=crypto.randomUUID();
    const send=(data=listing) => rpc(B,'hocalist.hocatrends_submit_store_offer($1,$2::jsonb,$3::jsonb)',[key,JSON.stringify(offer),JSON.stringify(data)]);
    await assert.rejects(send(),/hocatrends_not_eligible/);
    await setPlan('elite');
    await assert.rejects(send({...listing,image_media_ids:[]}),/publication_photos/);
    await assert.rejects(send({...listing,image_media_ids:[priv]}),/publication_photos/);
    await assert.rejects(send({...listing,title:''}),/title/);
    assert.equal((await db.query('SELECT count(*) AS n FROM hocalist.offers WHERE request_id=$1',[req.id])).rows[0].n,0);
    const sent=await send();
    assert.equal((await send()).id,sent.id);
    const copy=(await db.query('SELECT * FROM hocalist.store_listings WHERE source_offer_id=$1',[sent.id])).rows;
    assert.equal(copy.length,1);
    const l=copy[0];
    assert.equal(l.description,'');
    assert.equal(l.title,'Office chair');
    assert.deepEqual((await items(l.id)),[]);
    await approve(l.id);
    assert.equal((await items(l.id))[0].offer_price_minor,20000);
    await cmd(B,'store.update',{...storeInput,title:l.title,listing_id:l.id,expected_revision:l.revision,price_label:'250'});
    await approve(l.id);
    const result=(await items(l.id))[0];
    assert.equal(result.listing_id,l.id);
    assert.equal(result.offer_price_minor,25000);
    assert.deepEqual(result.offer_image_media_ids,[pub]);
    assert.equal((await trends()).find(t=>t.listing_id===l.id).price_label,'$250');
    const buyerOffer=await rpc(A,'hocalist.marketplace_offer($1)',[sent.id]);
    assert.equal(buyerOffer.revisions[0].price_minor,20000);
    await pref(B,l.id,false);
    await send();
    assert.deepEqual(await items(l.id),[]);
  } finally { await db.close(); }
});

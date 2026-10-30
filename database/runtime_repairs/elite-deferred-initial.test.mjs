import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createCommercialDb,IDS,callAs} from '../commercial_completion/tests/fixture.mjs';
const migration=new URL('../../supabase/migrations/20261027065137_elite_deferred_initial_fee.sql',import.meta.url);
const read=p=>readFile(new URL(p,import.meta.url),'utf8');

test('Elite settlement boundaries for wallet and card funding',async t=>{
 const db=await createCommercialDb();
 try{
  for(const p of ['../chat/012_credit_qualification.sql','./207_offer_submission_fee.sql','./228_target_fee_policy.sql','./231_deal_chat_threads.sql','./235_paygo_payment_setup.sql','./236_paygo_collection.sql','./237_paygo_event_reconciliation.sql']) await db.exec(await read(p));
  await db.exec('UPDATE hocalist.paygo_collection_policy SET enabled=true');
  await db.query("INSERT INTO hocalist.seller_entitlements(user_id,plan_code,source) VALUES($1,'elite','admin') ON CONFLICT(user_id) DO UPDATE SET plan_code='elite'",[IDS.seller]);
  const setup=crypto.randomUUID();
  await db.query("INSERT INTO hocalist.paygo_payment_setups(id,user_id,membership_id,request_key,customer_id,state,consent_version) VALUES($1,$2,$3,gen_random_uuid(),'cus_Elite','complete','paygo-v1')",[setup,IDS.seller,IDS.sellerMembership]);
  await db.query("INSERT INTO hocalist.paygo_payment_methods(user_id,setup_id,customer_id,payment_method_id,consent_version) VALUES($1,$2,'cus_Elite','pm_Elite','paygo-v1')",[IDS.seller,setup]);
  async function seed(kind='prepaid',{due=false,qualified=true,forfeit=false}={}){
   const request=crypto.randomUUID(),offer=crypto.randomUUID();
   await db.query("INSERT INTO hocalist.requests(id,buyer_user_id,buyer_profile_id,kind,title,condition,status,first_accepted_at,acceptance_expires_at) VALUES($1,$2,$3,'product','Synthetic Elite settlement','used','active',now()-interval '7 days',now()+$4::interval)",[request,IDS.buyer,IDS.buyerMembership,due?'-1 second':'7 days']);
   await db.query("INSERT INTO hocalist.offers(id,request_id,buyer_user_id,seller_user_id,seller_profile_id,status) VALUES($1,$2,$3,$4,$5,'selected')",[offer,request,IDS.buyer,IDS.seller,IDS.sellerMembership]);
   let batch=null;
   if(kind==='prepaid')batch=(await db.query("SELECT hocalist.credit_deposit_internal($1,$2,2000,155,375,'elite-test') AS d",[IDS.seller,crypto.randomUUID()])).rows[0].d;
   const target=(await db.query("INSERT INTO hocalist.credit_targets(user_id,request_id,offer_id,batch_id,funding_kind,initial_minor,winning_minor,reserved_minor,week_start,rate_version,qualified_at,competitors_viewed_at) VALUES($1,$2,$3,$4,$5,155,375,$6,current_date,'elite-test',CASE WHEN $7 THEN now() END,CASE WHEN $8 THEN now() END) RETURNING id",[IDS.seller,request,offer,batch,kind,kind==='prepaid'?375:0,qualified,forfeit])).rows[0].id;
   if(batch)await db.query('UPDATE hocalist.credit_batches SET reserved_minor=375 WHERE id=$1',[batch]);
   return {target,request,offer};
  }
  const historical=await seed();
  await db.exec(await readFile(migration,'utf8'));
  const settle=(x,action='initial')=>db.query('SELECT hocalist.credit_settle_internal($1,$2)',[x.target,action]);
  const row=async x=>(await db.query('SELECT * FROM hocalist.credit_targets WHERE id=$1',[x.target])).rows[0];
  const jobs=async x=>(await db.query('SELECT * FROM hocalist.paygo_charges WHERE target_id=$1 ORDER BY phase',[x.target])).rows;
  async function purchase(x,seller=IDS.seller){
   const conversation=crypto.randomUUID(),meeting=crypto.randomUUID();
   await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[conversation,x.request,x.offer]);
   await db.query("INSERT INTO hocalist.meetings(id,conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,meeting_expires_at) VALUES($1,$2,$3,$4,$5,$6,'accepted',now()+interval '1 day')",[meeting,conversation,x.request,x.offer,IDS.buyer,seller]);
   await db.query('INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id) VALUES($1,$2,$3,gen_random_uuid(),$4,$5)',[x.request,meeting,x.offer,IDS.buyer,seller]);
  }
  await t.test('historical targets retain their original timing',async()=>{await settle(historical);assert.equal(Number((await row(historical)).charged_minor),155);});
  for(const kind of ['prepaid','paygo']){
   await t.test(`${kind}: reply records eligibility without collecting`,async()=>{const x=await seed(kind);await settle(x);await settle(x);assert.equal(Number((await row(x)).charged_minor),0);assert.equal((await jobs(x)).length,0);});
   await t.test(`${kind}: eligible day-seven expiry waives the fee`,async()=>{const x=await seed(kind,{due:true});await db.query('SELECT hocalist.credit_reconcile_target_internal($1)',[x.target]);assert.equal((await row(x)).status,'refunded');assert.equal(Number((await row(x)).charged_minor),0);assert.equal((await jobs(x)).length,0);});
   await t.test(`${kind}: forfeited refund collects once at the deadline`,async()=>{
    const x=await seed(kind,{due:true,forfeit:true});await settle(x);await settle(x);
    if(kind==='prepaid')assert.equal(Number((await row(x)).charged_minor),155);
    else assert.deepEqual((await jobs(x)).map(j=>[j.phase,Number(j.fee_minor)]),[['initial',155]]);
   });
   await t.test(`${kind}: own PIN before day seven settles only the total`,async()=>{
    const x=await seed(kind);await purchase(x);await settle(x,'win');await settle(x,'win');
    if(kind==='prepaid')assert.equal(Number((await row(x)).charged_minor),375);
    else assert.deepEqual((await jobs(x)).map(j=>[j.phase,Number(j.fee_minor)]),[['initial',155],['win',220]]);
   });
   await t.test(`${kind}: another seller's PIN makes the qualified initial fee due`,async()=>{
    const x=await seed(kind);await purchase(x,IDS.seller2);await settle(x,'release');await settle(x,'release');
    assert.equal(Number((await row(x)).charged_minor),kind==='prepaid'?155:0);
    assert.equal((await row(x)).status,kind==='prepaid'?'released':'reserved');
    assert.equal((await jobs(x)).length,kind==='prepaid'?0:1);
   });
   await t.test(`${kind}: no interaction never becomes chargeable at expiry`,async()=>{const x=await seed(kind,{due:true,qualified:false,forfeit:true});await settle(x);await settle(x,'release');assert.equal(Number((await row(x)).charged_minor),0);assert.equal((await jobs(x)).length,0);});
  }
  await t.test('private settlement helpers cannot be invoked by app roles',async()=>{
   for(const role of ['anon','authenticated','service_role'])await assert.rejects(callAs(db,role,IDS.seller,"SELECT hocalist.credit_settle_before_elite_timing($1,'initial')",[historical.target]),/permission denied/);
  });
  await t.test('card success after another seller wins is debited before releasing the target',async()=>{
   const x=await seed('paygo');await purchase(x,IDS.seller2);await settle(x,'release');
   const [j]=await jobs(x);
   await db.query("SELECT hocalist.paygo_charge_bind($1,'pi_EliteLoser')",[j.id]);
   await db.query("SELECT hocalist.paygo_charge_finish($1,'pi_EliteLoser','cus_Elite',155,'succeeded')",[j.id]);
   await settle(x,'release');await settle(x,'release');
   assert.equal((await row(x)).status,'released');assert.equal(Number((await row(x)).charged_minor),155);assert.equal((await jobs(x)).length,1);
  });
  await t.test('wallet reconciliation cannot release a qualified declined offer before its deadline',async()=>{
   const x=await seed();await db.query("UPDATE hocalist.offers SET status='declined' WHERE id=$1",[x.offer]);
   await db.query('SELECT hocalist.credit_reconcile_internal($1)',[IDS.seller]);
   assert.equal((await row(x)).status,'reserved');assert.equal(Number((await row(x)).charged_minor),0);
  });
  await t.test('a valid meeting preserves the reservation for an eligible day-seven seller',async()=>{
   const x=await seed('prepaid',{due:true}),c=crypto.randomUUID();
   await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[c,x.request,x.offer]);
   await db.query("INSERT INTO hocalist.meetings(conversation_id,request_id,offer_id,buyer_user_id,seller_user_id,status,meeting_expires_at) VALUES($1,$2,$3,$4,$5,'accepted',now()+interval '1 day')",[c,x.request,x.offer,IDS.buyer,IDS.seller]);
   await db.query('SELECT hocalist.credit_reconcile_target_internal($1)',[x.target]);
   assert.equal((await row(x)).status,'reserved');assert.equal(Number((await row(x)).charged_minor),0);
  });
  await t.test('actual buyer replies qualify only their own deal without collecting Elite fees',async()=>{
   const a=await seed('prepaid',{qualified:false}),b=await seed('paygo',{qualified:false}),c=crypto.randomUUID();
   await db.query("INSERT INTO hocalist.conversations(id,origin,request_id,offer_id) VALUES($1,'targeted_request',$2,$3)",[c,a.request,a.offer]);
   await db.query('UPDATE hocalist.offers SET conversation_id=$1 WHERE id=ANY($2::uuid[])',[c,[a.offer,b.offer]]);
   await db.query("INSERT INTO hocalist.conversation_members(conversation_id,user_id,profile_id,role) VALUES($1,$2,$3,'buyer'),($1,$4,$5,'seller')",[c,IDS.buyer,IDS.buyerMembership,IDS.seller,IDS.sellerMembership]);
   const send=(u,x,key)=>callAs(db,'authenticated',u,'SELECT hocalist.chat_deal_send($1,$2,$3,$4)',[c,x.offer,key,'Synthetic Elite reply test']);
   await send(IDS.seller,a,'elite-seller-a');await send(IDS.buyer,a,'elite-buyer-a');await send(IDS.buyer,a,'elite-buyer-a');
   assert.ok((await row(a)).qualified_at);assert.equal((await row(b)).qualified_at,null);
   await send(IDS.seller,b,'elite-seller-b');await send(IDS.buyer,b,'elite-buyer-b');
   assert.ok((await row(b)).qualified_at);
   for(const x of [a,b]){assert.equal(Number((await row(x)).charged_minor),0);assert.equal((await jobs(x)).length,0);}
  });
  await t.test('bounded sweep handles new due deals without touching historical or future targets',async()=>{
   const due=await seed('prepaid',{due:true,forfeit:true}),future=await seed('prepaid',{forfeit:true});
   const before=Number((await row(historical)).charged_minor);
   const n=(await db.query('SELECT hocalist.credit_elite_due_sweep(1000) AS n')).rows[0].n;
   assert.ok(n>0);assert.equal(Number((await row(due)).charged_minor),155);
   assert.equal(Number((await row(future)).charged_minor),0);
   assert.equal(Number((await row(historical)).charged_minor),before);
   await assert.rejects(db.query('SELECT hocalist.credit_elite_due_sweep(1001)'),/invalid_limit/);
   await assert.rejects(callAs(db,'authenticated',IDS.seller,'SELECT hocalist.credit_elite_due_sweep(1)'),/permission denied/);
  });
  await t.test('winning requires this seller’s PIN confirmation and qualification',async()=>{
   const x=await seed();await assert.rejects(settle(x,'win'),/purchase_confirmation_required/);
   const y=await seed('prepaid',{qualified:false});await purchase(y);await settle(y,'win');assert.equal(Number((await row(y)).charged_minor),0);
  });
  await t.test('Free and Pro retain immediate qualification timing',async()=>{
   for(const plan of ['free','pro']){
    await db.query('UPDATE hocalist.seller_entitlements SET plan_code=$1 WHERE user_id=$2',[plan,IDS.seller]);
    for(const kind of ['prepaid','paygo']){const x=await seed(kind);await settle(x);assert.equal((await row(x)).elite_deferred_initial,false);assert.equal(Number((await row(x)).charged_minor),kind==='prepaid'?155:0);assert.equal((await jobs(x)).length,kind==='paygo'?1:0);}
   }
  });
 }finally{await db.close();}
});

import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {setup,A,B,C,acceptedDeal,callAs} from '../../outcomes/tests/fixture.mjs';
test('private image ownership and attachment authorization',async()=>{
 const db=await setup();try{
 const deal=await acceptedDeal(db);
 await db.exec(await readFile(new URL('../100_private_images.sql',import.meta.url),'utf8'));
 const rpc=async(user,action,input)=>(await callAs(db,'service_role',null,'SELECT hocalist.media_gateway($1,$2,$3) AS v',[user,action,JSON.stringify(input)]))[0].v;
 const input={key:'80000000-0000-4000-8000-000000000001',purpose:'offer',hash:'a'.repeat(64)};
 const image=await rpc(B,'begin',input);assert.equal((await rpc(B,'begin',input)).id,image.id);
 await assert.rejects(rpc(B,'begin',{...input,hash:'b'.repeat(64)}),/idempotency_conflict/);
 await assert.rejects(rpc(A,'begin',{...input,key:'80000000-0000-4000-8000-000000000002'}),/media_access_denied/);
 await assert.rejects(rpc(C,'complete',{id:image.id,size:100,width:10,height:10}),/media_not_found/);
 await rpc(B,'complete',{id:image.id,size:100,width:10,height:10});
 await assert.rejects(rpc(A,'read',{id:image.id}),/media_access_denied/);
 const rev=(await db.query('SELECT * FROM hocalist.offer_revisions WHERE offer_id=$1',[deal.offerId])).rows[0];
 const append=async(media)=>db.query(`INSERT INTO hocalist.offer_revisions
 SELECT (jsonb_populate_record(NULL::hocalist.offer_revisions,to_jsonb(r)||jsonb_build_object('id',gen_random_uuid(),'sequence',r.sequence+1,'image_media_ids',$2::jsonb))).*
 FROM hocalist.offer_revisions r WHERE r.id=$1`,[rev.id,JSON.stringify(media)]);
 await assert.rejects(append(['80000000-0000-4000-8000-000000000099']),/invalid_media_reference/);
 await append([image.id]);
 await db.query('UPDATE hocalist.offer_revisions SET image_media_ids=$1 WHERE id=$2',[JSON.stringify([image.id]),rev.id]);
 assert.equal((await rpc(A,'read',{id:image.id})).id,image.id);
 await assert.rejects(rpc(C,'read',{id:image.id}),/media_access_denied/);
 await assert.rejects(callAs(db,'authenticated',B,'SELECT * FROM hocalist.media_images'),/permission denied/);
 await assert.rejects(callAs(db,'authenticated',B,"SELECT hocalist.media_gateway($1,'read',$2)",[B,JSON.stringify({id:image.id})]),/permission denied/);
 }finally{await db.close();}
});

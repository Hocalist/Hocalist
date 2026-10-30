import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,C,acceptedDeal,callAs} from '../outcomes/tests/fixture.mjs';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('offer changes invalidate participant chat without exposing terms',async()=>{
 const db=await setup();try {
  await db.exec(await read('../communication_completion/150_chat_block.sql'));
  await db.exec(await read('../communication_completion/154_chat_realtime_signals.sql'));
  const deal=await acceptedDeal(db);
  const sql=await read('./211_offer_change_signals.sql');await db.exec(sql);await db.exec(sql);
  const count=async()=>Number((await db.query('SELECT count(*) n FROM hocalist.chat_change_signals WHERE conversation_id=$1',[deal.conversationId])).rows[0].n);
  const before=await count();
  await db.query('UPDATE hocalist.offers SET revision=revision+1 WHERE conversation_id=$1',[deal.conversationId]);
  assert.ok(await count()>before);
  const next=await count();
  await db.query('UPDATE hocalist.offer_revisions SET message=message WHERE offer_id IN (SELECT id FROM hocalist.offers WHERE conversation_id=$1)',[deal.conversationId]);
  assert.ok(await count()>next);
  assert.ok((await callAs(db,'authenticated',A,'SELECT * FROM hocalist.chat_change_signals')).length>0);
  assert.equal((await callAs(db,'authenticated',C,'SELECT * FROM hocalist.chat_change_signals')).length,0);
  await assert.rejects(callAs(db,'authenticated',A,'SELECT hocalist.chat_signal_on_offer_change()'),/permission denied/);
  await db.exec('ALTER TABLE hocalist.offers DISABLE TRIGGER chat_signal_offer_change');
  await assert.rejects(db.exec(sql),/trigger drift/);
 }finally{await db.close();}
});

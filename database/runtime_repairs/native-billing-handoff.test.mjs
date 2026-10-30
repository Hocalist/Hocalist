import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {setup,A,B,callAs} from '../outcomes/tests/fixture.mjs';

test('native billing receipts enforce seller identity, expiry, one-use and denied direct access',async t=>{
 const db=await setup(false);
 const receipt=(user,action,digest)=>callAs(db,'authenticated',user,
   'SELECT hocalist.native_billing_receipt($1,$2) AS allowed',[action,digest]);
 try {
  await db.exec(await readFile(new URL('./212_native_billing_handoff.sql',import.meta.url),'utf8'));
  const one='ab'.repeat(32),two='cd'.repeat(32);
  await t.test('buyer and unauthenticated callers cannot issue',async()=>{
   await assert.rejects(receipt(A,'register',one),/billing_access_denied/);
   await assert.rejects(callAs(db,'anon',null,'SELECT hocalist.native_billing_receipt($1,$2)', ['register',one]),/permission denied/);
  });
  await t.test('receipt is consumed once and a new issue invalidates the previous one',async()=>{
   assert.equal((await receipt(B,'register',one))[0].allowed,true);
   await receipt(B,'register',two);
   assert.equal((await receipt(B,'consume',one))[0].allowed,false);
   assert.equal((await receipt(B,'consume',two))[0].allowed,true);
   assert.equal((await receipt(B,'consume',two))[0].allowed,false);
  });
  await t.test('expiry and table access are enforced',async()=>{
   await receipt(B,'register',one);
   await db.exec("UPDATE hocalist.native_billing_receipts SET expires_at=now()-interval '1 second'");
   assert.equal((await receipt(B,'consume',one))[0].allowed,false);
   await assert.rejects(callAs(db,'authenticated',B,'SELECT * FROM hocalist.native_billing_receipts'),/permission denied/);
  });
 } finally {await db.close();}
});

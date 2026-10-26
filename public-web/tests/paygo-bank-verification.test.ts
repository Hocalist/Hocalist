import {test} from 'node:test';
import assert from 'node:assert/strict';
import {verifyPaygoBankPayment} from '../app/billing/paygo-bank-verification';
test('bank verification accepts only TEST capabilities and never treats browser success as ledger settlement',async()=>{
 const previous=(globalThis as unknown as {window:unknown}).window;
 let called=0,secretUsed='';
 try{
  (globalThis as unknown as {window:unknown}).window={Stripe:(key:string)=>{assert.equal(key,'pk_test_Synthetic');return {confirmCardPayment:async(secret:string)=>{called++;secretUsed=secret;return {};}};}};
  await assert.rejects(verifyPaygoBankPayment('pk_live_Test','pi_Test_secret_Synthetic'),/unavailable/);assert.equal(called,0);
  await assert.rejects(verifyPaygoBankPayment('pk_test_Synthetic','invalid'),/unavailable/);assert.equal(called,0);
  await verifyPaygoBankPayment('pk_test_Synthetic','pi_Test_secret_Synthetic');assert.equal(secretUsed,'pi_Test_secret_Synthetic');assert.equal(called,1);
  (globalThis as unknown as {window:unknown}).window={Stripe:()=>({confirmCardPayment:async()=>({error:{message:'provider-private-details'}})})};
  await assert.rejects(verifyPaygoBankPayment('pk_test_Synthetic','pi_Test_secret_Synthetic'),error=>error instanceof Error&&!error.message.includes('provider-private-details'));
 }finally{(globalThis as unknown as {window:unknown}).window=previous;}
});

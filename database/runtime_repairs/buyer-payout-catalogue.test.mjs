import {readFile} from "node:fs/promises";
import assert from "node:assert/strict";
import {test} from "node:test";
import {createCommercialDb,IDS} from "../commercial_completion/tests/fixture.mjs";
test("catalogue choices are repeatable and recipient mappings remain private", async()=>{
 const db=await createCommercialDb();
 try{
  for(const name of ["274_buyer_catalogue_choices","275_stripe_reward_recipients"]){
   const sql=await readFile(new URL("./"+name+".sql",import.meta.url),"utf8");
   await db.exec(sql);await db.exec(sql);
  }
  assert.equal((await db.query("select label from hocalist.catalogue_categories where slug='electronics' and scope='product' and status='active'")).rows.length,1);
  assert.equal((await db.query("select label from hocalist.catalogue_categories where slug='cleaning' and scope='service' and status='active'")).rows.length,1);
  assert.equal((await db.query("select has_function_privilege('authenticated','hocalist.stripe_reward_destination_internal(uuid,text)','execute') ok")).rows[0].ok,false);
  assert.equal((await db.query("select has_table_privilege('authenticated','hocalist.stripe_reward_recipients','insert') ok")).rows[0].ok,false);
 } finally{await db.close()}
});

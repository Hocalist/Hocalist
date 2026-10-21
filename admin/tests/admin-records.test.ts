import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeRecordPage, decodeOverview } from "../app/lib/admin-records";
const id="10000000-0000-4000-8000-000000000001";
const row={id,cells:[id,"Name","buyer","active","Area","2026-09-23"]};
test("records decoder accepts bounded pages and explicit empty states",()=>{
  assert.deepEqual(decodeRecordPage({items:[],next_cursor:null}),{items:[],next_cursor:null});
  assert.equal(decodeRecordPage({items:[row],next_cursor:id})?.items.length,1);
});
test("records decoder refuses malformed or duplicate rows and invalid cursors",()=>{
  for(const payload of [null,{}, {items:[row,row],next_cursor:null},
    {items:[{...row,cells:[1,2,3,4,5,6]}],next_cursor:null},
    {items:[{...row,id:"other"}],next_cursor:null}, {items:[row],next_cursor:"invalid"},
    {items:[row],next_cursor:"10000000-0000-4000-8000-000000000002"},
    {items:[{...row,cells:["x".repeat(2001),"","","","",""]}],next_cursor:null}])
    assert.equal(decodeRecordPage(payload),null);
});
test("overview requires every nonnegative safe count",()=>{
  const valid={active_memberships:0,open_requests:1,submitted_offers:2,listings_in_review:3,test_subscriptions:0};
  assert.deepEqual(decodeOverview(valid),valid);
  for(const invalid of [null,{}, {...valid,open_requests:-1},{...valid,open_requests:"2"},{...valid,open_requests:Infinity}])
    assert.equal(decodeOverview(invalid),null);
});

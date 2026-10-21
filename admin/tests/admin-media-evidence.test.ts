import { test } from "node:test";
import assert from "node:assert/strict";
import { mediaEvidenceResolver } from "../app/lib/admin-media-evidence";
import { handleEvidenceCore, type CoreRequest } from "../app/lib/admin-http";

const mediaId = "90000000-0000-4000-8000-000000000001";
const config = { url: "https://project.supabase.co", anonKey: "public-test-key" };
const token = `header.${Buffer.from(JSON.stringify({sub:mediaId,exp:9999999999,aal:"aal2"})).toString("base64url")}.signature`;
const req: CoreRequest = {
  method:"POST",origin:"https://admin.hocalist.com",host:"admin.hocalist.com",
  secFetchSite:"same-origin",sessionToken:token,refreshToken:null,pendingToken:null,nextPath:null,
  body:{submission_id:mediaId,media_id:mediaId},
};

test("accounts byte gateway connects only after the admin reference check", async () => {
  const calls: string[] = [];
  const fetchImpl = (async (input, init) => {
    const url = String(input); calls.push(url);
    assert.equal(new Headers(init?.headers).get("Authorization"), `Bearer ${token}`);
    if (url.includes("/rest/v1/rpc/admin_evidence_reference")) return Response.json({reference_ok:true});
    assert.equal(new URL(url).pathname, "/functions/v1/hocalist-media");
    assert.equal(new URL(url).searchParams.get("id"), mediaId);
    assert.equal(init?.redirect, "error");
    return new Response(new Uint8Array([255,216,255,217]), {headers:{"Content-Type":"image/jpeg"}});
  }) as typeof fetch;
  const result = await handleEvidenceCore(req, {config,isProduction:false,mfaPolicy:"off",evidenceHost:null,fetchImpl}, mediaEvidenceResolver);
  assert.equal(result.status,200); assert.deepEqual([...result.image!],[255,216,255,217]);
  assert.deepEqual(result.body,{}); assert.equal(calls.length,2);
});

test("denied reference never reads evidence bytes", async () => {
  let calls=0;
  const fetchImpl=(async()=>{calls++;return Response.json({reference_ok:false});}) as typeof fetch;
  const result=await handleEvidenceCore(req,{config,isProduction:false,mfaPolicy:"off",evidenceHost:null,fetchImpl},mediaEvidenceResolver);
  assert.equal(result.status,404);assert.equal(calls,1);assert.equal(result.image,undefined);
});

test("gateway refuses HTML, oversized images and provider failure", async () => {
  for (const response of [
    new Response("<html>secret error</html>",{headers:{"Content-Type":"text/html"}}),
    new Response(new Uint8Array(4*1024*1024+1),{headers:{"Content-Type":"image/jpeg"}}),
    new Response("private diagnostic",{status:403}),
  ]) {
    const result=await mediaEvidenceResolver.resolveEvidence({mediaId,submissionId:mediaId,accessToken:token,config,fetchImpl:(async()=>response) as typeof fetch});
    assert.equal(result.state,"unavailable");assert.equal(JSON.stringify(result).includes("private diagnostic"),false);
  }
});

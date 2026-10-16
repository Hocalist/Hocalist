import {test} from 'node:test';
import assert from 'node:assert/strict';
import {decodePublicStore,loadPublicStore} from '../app/lib/public-store';
const id='10000000-0000-4000-8000-00000000000b';
test('invalid Store identifiers never reach the provider',async()=>{
  let calls=0; const fake=(async()=>{calls++;throw new Error('no');}) as typeof fetch;
  assert.deepEqual(await loadPublicStore('bad', {url:'https://test.example',anonKey:'public'},fake),{available:false});assert.equal(calls,0);
});
test('public Store read forwards no user credentials and uses the Hocalist schema',async()=>{
  const fake=(async(input,init)=>{assert.equal(String(input),'https://test.example/rest/v1/rpc/public_store');assert.equal((init?.headers as Record<string,string>)['Content-Profile'],'hocalist');assert.equal((init?.headers as Record<string,string>).Authorization,undefined);assert.equal((init as RequestInit & {cache:string})?.cache,'no-store');return new Response(JSON.stringify({available:true,name:'Seller',area:null,items:[]}));}) as typeof fetch;
  assert.equal((await loadPublicStore(id,{url:'https://test.example',anonKey:'public'},fake))?.available,true);
});
test('public Store decoder excludes unexpected private fields',()=>{
  const result=decodePublicStore({available:true,name:'Seller',area:null,contact:'PRIVATE',items:[]});assert.equal('contact' in result,false);
  assert.throws(()=>decodePublicStore({available:true,name:'Seller',area:null,items:[{id,title:'bad'}]}));
});


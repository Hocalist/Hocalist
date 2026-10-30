import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { shell, escapeHtml } from './build.mjs';
const manifest = JSON.parse(readFileSync(new URL('./manifest.json',import.meta.url)));
test('all authentication and security messages have branded accessible structure',()=>{
 assert.equal(manifest.length,13);
 for(const entry of manifest){
  const html=readFileSync(new URL(entry.file,import.meta.url),'utf8');
  assert.match(html,/<html lang="en">/); assert.match(html,/#00036c/);
  assert.match(html,/alt="Hocalist"/); assert.match(html,/max-width:560px/);
  assert.match(html,/https:\/\/www.hocalist.com\/support/);
  assert.doesNotMatch(html,/<script|<form|trycloudflare|sendgrid.net|postaneur|http:\/\//i);
  if(entry.category==='authentication' && entry.id!=='reauthentication'){
   assert.equal((html.match(/href="\{\{ \.ConfirmationURL \}\}"/g)||[]).length,1);
  }else if(entry.id==='reauthentication') assert.match(html,/\{\{ \.Token \}\}/);
  else assert.doesNotMatch(html,/ConfirmationURL|TokenHash|\.Token/);
 }
});
test('message copy escapes HTML rather than introducing user markup',()=>{
 assert.equal(escapeHtml('<img onerror="x">'),'&lt;img onerror=&quot;x&quot;&gt;');
 assert.doesNotMatch(shell({title:'<script>x</script>',body:'<img src=x>'}),/<script|<img src=x>/);
});
test('shared shell rejects unsafe action destinations and escapes ordinary codes',()=>{
 for (const href of ['javascript:alert(1)','https://evil.example/','https://www.hocalist.com@evil.example/']) {
  assert.throws(()=>shell({title:'Test',body:'Test',action:'Continue',href}));
 }
 assert.match(shell({title:'Test',body:'Test',code:'<script>'}),/&lt;script&gt;/);
});
test('brand surfaces retain solid fallback and Gmail dark-mode protection',()=>{
 const html=shell({title:'Test',body:'Test',action:'Continue',href:'{{ .ConfirmationURL }}'});
 assert.equal((html.match(/background-image:linear-gradient\(#00036c,#00036c\)/g)||[]).length,2);
 assert.match(html,/u \+ .hocalist-email .gmail-blend-screen/);
 assert.match(html,/class="brand-button"/);
 assert.match(html,/gmail-blend-difference">Continue/);
 assert.match(html,/prefers-color-scheme:dark/);
 assert.equal((html.match(/href="\{\{ \.ConfirmationURL \}\}"/g)||[]).length,1);
 assert.doesNotMatch(html,/Button not working|Copy this exact link/);
});

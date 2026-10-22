import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
test('admin uses one approved palette without legacy overrides',()=>{
 const app=join(process.cwd(),'app');
 assert.match(readFileSync(join(app,'design-tokens.css'),'utf8'),/--primary:#00036c/);
 const layout=readFileSync(join(app,'layout.tsx'),'utf8');
 assert.ok(layout.indexOf('./design-tokens.css')<layout.indexOf('./globals.css'));
 for(const file of ['globals.css','workspace.css']) {
  const css=readFileSync(join(app,file),'utf8');
  assert.doesNotMatch(css,/:root\s*\{/);
  assert.doesNotMatch(css,/#(?:005c86|0e76a8|004b70|004c6e|0d526f|22282b)\b/i);
 }
});

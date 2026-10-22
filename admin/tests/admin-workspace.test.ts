import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {Status} from '../app/components';
import {SectionTabs} from '../app/section-tabs';
test('negative statuses never inherit positive substring styling',()=>{
 for(const label of ['inactive','unverified','disabled','cancelled']){
  const html=renderToStaticMarkup(createElement(Status,null,label));
  assert.match(html,/status neutral/);assert.doesNotMatch(html,/status success/);
 }
 for(const label of ['failed','restricted','past_due'])assert.match(renderToStaticMarkup(createElement(Status,null,label)),/status danger/);
});
test('section tabs expose one selected panel while retaining both section contents',()=>{
 const html=renderToStaticMarkup(createElement(SectionTabs,{label:'Billing sections',sections:[{title:'Subscriptions',content:createElement('p',null,'Subscription controls')},{title:'Credits & rewards',content:createElement('p',null,'Ledger controls')}]}));
 assert.equal((html.match(/aria-selected="true"/g)||[]).length,1);
 assert.equal((html.match(/role="tabpanel"/g)||[]).length,2);
 assert.match(html,/hidden=""/);assert.match(html,/Subscription controls/);assert.match(html,/Ledger controls/);
});

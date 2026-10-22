import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {SectionHelp} from '../app/section-help';
import {FieldHelp} from '../app/field-help';
test('page help has an explicit accessible action and a closed explanation panel',()=>{
 const html=renderToStaticMarkup(createElement(SectionHelp,{path:'/requests',title:'Buyer requests'}));
 assert.match(html,/aria-label="About Buyer requests"/);assert.match(html,/Exact buyer addresses are not shown/);assert.doesNotMatch(html,/<dialog[^>]* open/);
});
test('field help remains available to keyboard users without scripts',()=>{
 const html=renderToStaticMarkup(createElement(FieldHelp,{label:'Winning fee',children:'The total includes the initial fee.'}));
 assert.match(html,/<details/);assert.match(html,/<summary aria-label="Explain Winning fee"/);assert.match(html,/total includes the initial fee/);
});

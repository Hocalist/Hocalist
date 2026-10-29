import {test} from 'node:test';
import assert from 'node:assert/strict';
import {decodeReportCreditTargets} from '../app/lib/admin-credit-returns';
test('report credit targets refuse fabricated or duplicate monetary rows',()=>{
 const row={id:'10000000-0000-4000-8000-000000000001',title:'Synthetic deal',fee_minor:145,status:'initial_charged',returned:false};
 assert.equal(decodeReportCreditTargets([row])?.length,1);
 assert.equal(decodeReportCreditTargets([row,row]),null);
 assert.equal(decodeReportCreditTargets([{...row,fee_minor:-1}]),null);
 assert.equal(decodeReportCreditTargets([{...row,fee_minor:1.5}]),null);
});

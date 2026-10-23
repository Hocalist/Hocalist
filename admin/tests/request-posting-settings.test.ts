import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseActiveRequestLimit,parseRequestPostingSettings} from '../app/lib/request-posting-settings';
import {parseAdminRpcBody} from '../app/lib/admin-rules';
test('request limit validates saved configuration and input',()=>{
 assert.deepEqual(parseRequestPostingSettings({maximum_active_requests:4,revision:1}),{maximum_active_requests:4,revision:1});
 for(const value of [null,{}, {maximum_active_requests:0,revision:1},{maximum_active_requests:4,revision:0},{maximum_active_requests:'4',revision:1}])assert.equal(parseRequestPostingSettings(value),null);
 for(const value of ['0','-1','1.5','101','','4e1'])assert.equal(parseActiveRequestLimit(value),null);
 assert.equal(parseActiveRequestLimit('4'),4);
 assert.equal(parseAdminRpcBody({function:'admin_request_posting_settings',params:{}}).ok,true);
});

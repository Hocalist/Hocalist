import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {standardWalletAmount} from '../app/billing/funding-amount';
import CreditFundingDialog from '../app/billing/CreditFundingDialog';
import PlanChangeDialog from '../app/billing/PlanChangeDialog';
import {isCurrentPlan,planBenefits} from '../app/billing/plan-presentation';
import {parseCheckoutBody} from '../app/lib/website-rules';
import PlanTargetingFees from '../app/billing/PlanTargetingFees';
import PaygoPaymentSetup from '../app/billing/PaygoPaymentSetup';

test('normal billing preview has no fabricated debt or revoke controls',()=>{
 const html=renderToStaticMarkup(createElement(PaygoPaymentSetup,{preview:true}));
 assert.equal(html,'');
 const setup=renderToStaticMarkup(createElement(PaygoPaymentSetup,{preview:true,setupOnly:true}));
 assert.match(setup,/Save card securely/);assert.doesNotMatch(setup,/Revoke|Turn off|Example request|Payments needing attention|Save another card/);
});

test('each comparison card has collapsible server targeting rates in HC',()=>{
 const html=renderToStaticMarkup(createElement(PlanTargetingFees,{rates:{plan_code:'elite',initial_minor:180,winning_minor:450,deposits:[{amount_minor:2000,initial_fee_minor:155,winning_total_minor:375},{amount_minor:4000,initial_fee_minor:145,winning_total_minor:325}]}}));
 assert.match(html,/<details[^>]*>/);assert.doesNotMatch(html,/<details[^>]*open/);
 const text=html.replace(/<[^>]*>/g,' ').replace(/\s+/g,' ');
 for(const value of ['Targeting fees','1.80 HC','4.50 HC','20 HC','40 HC','1.55 HC','3.75 HC','1.45 HC','3.25 HC'])assert.ok(text.includes(value),value);
 assert.doesNotMatch(html,/\$/);
 assert.match(renderToStaticMarkup(createElement(PlanTargetingFees,{})),/not available right now/);
});

test('standard checkout accepts an exact bounded amount instead of a catalogue option',()=>{
 const idempotencyKey='2f0c9d1a-0000-4000-8000-000000000001';
 assert.deepEqual(parseCheckoutBody({kind:'credit_deposit',amountMinor:1250,idempotencyKey}),{ok:true,value:{kind:'credit_deposit',amountMinor:1250,idempotencyKey}});
 for(const amountMinor of [0,49,2000,200.5,'1250',null])assert.equal(parseCheckoutBody({kind:'credit_deposit',amountMinor,idempotencyKey}).ok,false);
 assert.equal(parseCheckoutBody({kind:'credit_deposit',amountMinor:1250,optionId:idempotencyKey,idempotencyKey}).ok,false);
});

test('current subscription matches the verified billing period, not only the tier',()=>{
 assert.equal(isCurrentPlan(true,'pro','month','pro','month'),true);
 assert.equal(isCurrentPlan(true,'pro','month','pro','year'),false);
 assert.equal(isCurrentPlan(true,'pro',undefined,'pro','month'),false);
 assert.equal(isCurrentPlan(true,'elite','year','pro','year'),false);
 assert.equal(isCurrentPlan(false,'pro','month','pro','month'),false);
});
test('comparison plans retain their complete tier benefits and server limits',()=>{
 const entitlement={plans:[{plan_code:'pro',weekly_target_limit:50,store_listing_limit:15},{plan_code:'elite',weekly_target_limit:100,store_listing_limit:50}]};
 assert.ok(planBenefits('pro',entitlement).includes('Contacts dashboard'));
 assert.ok(planBenefits('pro',entitlement).includes('Target up to 50 weekly customers'));
 assert.ok(planBenefits('elite',entitlement).includes('Customer insights'));
 assert.ok(planBenefits('elite',entitlement).includes('View competing offers after buyer acceptance'));
 const html=renderToStaticMarkup(createElement(PlanChangeDialog,{target:'pro:year',onClose:()=>{},onContinue:()=>{},busy:false,entitlement}));
 assert.match(html,/Switch to Pro Seller · Annual/);assert.match(html,/50.*weekly customer targets/);
});

test('standard wallet input preserves exact credit cents and rejects out-of-band amounts',()=>{
 for(const [input,expected] of [['0.50',50],['1',100],[' 12.3 ',1230],['19.99',1999]] as const) assert.equal(standardWalletAmount(input),expected);
 for(const input of ['','0','0.49','20','40','-1','1.001','1e1','Infinity','NaN','2,00','9007199254740991']) assert.equal(standardWalletAmount(input),null,input);
});
test('credit popup includes discounted packs and both standard funding choices with server rates',()=>{
 const html=renderToStaticMarkup(createElement(CreditFundingDialog,{open:true,onClose:()=>{},busy:false,allowed:true,preview:true,standardEnabled:false,options:[{id:'twenty',amount_minor:2000,initial_fee_minor:175,winning_total_minor:460},{id:'forty',amount_minor:4000,initial_fee_minor:165,winning_total_minor:450}],standard:{plan_code:'pro',initial_minor:190,winning_minor:475},onChoose:()=>{},onCustom:()=>{}}));
 for(const text of ['20 HC','40 HC','Wallet amount','Card','1.90 HC','4.75 HC','Adding credits does not charge a targeting fee.']) assert.ok(html.includes(text),text);
 assert.match(html,/<dialog/);assert.doesNotMatch(html,/Unlimited|Stripe TEST/);
});
test('downgrade review explains limits and keeps change behind provider confirmation',()=>{
 const html=renderToStaticMarkup(createElement(PlanChangeDialog,{target:'free',onClose:()=>{},onContinue:()=>{},busy:false,entitlement:{plans:[{plan_code:'free',weekly_target_limit:10,store_listing_limit:3}],store_listing:{active:8,limit:15}}}));
 for(const text of ['Switch to Free','10 weekly customer targets','3 active listings','8 active listings','unchanged until you confirm','Keep current plan','Choose cancellation']) assert.ok(html.includes(text),text);
});

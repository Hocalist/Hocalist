import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import SellerBillingOverview from '../app/billing/SellerBillingOverview';
import PaygoPaymentSetup from '../app/billing/PaygoPaymentSetup';
import {paygoReturn} from '../app/billing/paygo-return';

test('card setup returns select their own controls and reject malformed setup identities',()=>{
 assert.equal(paygoReturn(new URLSearchParams('paygo_setup=90000000-0000-4000-8000-000000000002')).setupId,'90000000-0000-4000-8000-000000000002');
 assert.equal(paygoReturn(new URLSearchParams('paygo_setup=invalid')).setupId,null);
 assert.equal(paygoReturn(new URLSearchParams('paygo_cancelled=1')).cancelled,true);
 assert.deepEqual(paygoReturn(new URLSearchParams('checkout=90000000-0000-4000-8000-000000000002')),{setupId:null,cancelled:false});
});

test('card setup waits for status before declaring that it is unavailable',()=>{
 const html=renderToStaticMarkup(createElement(PaygoPaymentSetup,{setupOnly:true}));
 assert.match(html,/Checking card setup/);
 assert.match(html,/hocalist-icon.png/);
 assert.match(html,/aria-busy="true"/);
 assert.doesNotMatch(html,/not available|Save card securely/);
});
test('billing design renders approved section order with server rates, limits and supplied artwork',()=>{
 const html=renderToStaticMarkup(createElement(SellerBillingOverview,{plan:'pro',entitlement:{plans:[{plan_code:'pro',weekly_target_limit:67,store_listing_limit:19}]},options:[{id:'option',amount_minor:2000,initial_fee_minor:175,winning_total_minor:460}],standard:{plan_code:'pro',initial_minor:190,winning_minor:475},priceLabel:'$120.00 / year',accessLabel:'Active subscription',onAddCredits:()=>{},onSelectPlan:()=>{}}));
 assert.match(html,/67 weekly customers/);assert.match(html,/19 products or services/);
 assert.match(html,/pro-reference.jpg/);assert.match(html,/free-reference.jpg/);
 assert.match(html,/4\.75/);assert.match(html,/1\.90/);assert.match(html,/1\.75 HC/);assert.match(html,/4\.60 HC/);
 assert.ok(html.indexOf('Current plan')<html.indexOf('Targeting fees'));
 assert.ok(html.indexOf('Prepaid wallet savings')<html.indexOf('Wallet credits'));
 assert.ok(html.indexOf('Add credits')<html.indexOf('Compare seller plans'));
 assert.doesNotMatch(html,/Unlimited|Stripe TEST|Sending an offer charges/);
});
test('Free and Elite layouts preserve role-specific artwork and corrected policy wording',()=>{
 const render=(plan:string)=>renderToStaticMarkup(createElement(SellerBillingOverview,{plan,entitlement:{policy:{earned_pro_threshold:7},plans:[{plan_code:plan,weekly_target_limit:10,store_listing_limit:3}]},options:[],accessLabel:'Active',onAddCredits:()=>{},onSelectPlan:()=>{}}));
 assert.match(render('free'),/free-benefits/);assert.match(render('free'),/7 PIN-confirmed sales this month unlock Pro next month/);
 assert.match(render('elite'),/elite-reference.jpg/);assert.match(render('elite'),/after buyer acceptance/);
});

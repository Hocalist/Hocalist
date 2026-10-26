'use client';
import BillingDialog from './BillingDialog';
import type {BillingEntitlement} from './SellerBillingOverview';
export default function PlanChangeDialog({target,onClose,onContinue,busy,entitlement,paidUntil}:{target:string|null;onClose:()=>void;onContinue:()=>void;busy:boolean;entitlement?:BillingEntitlement;paidUntil?:string|null}){
 const [plan,interval]=target?.split(':')??[];
 const limits=entitlement?.plans?.find(row=>row.plan_code===plan),active=entitlement?.store_listing?.active;
 const name=plan==='free'?'Free':`${plan==='pro'?'Pro Seller':'Elite Seller'}${interval?` · ${interval==='year'?'Annual':'Monthly'}`:''}`;
 return <BillingDialog open={target!==null} onClose={onClose} busy={busy} eyebrow="Review your plan change" title={`Switch to ${name}`}>
  <p className="credit-funding-intro">Review the effective date and any payment adjustments in secure billing before confirming. Your plan is unchanged until you confirm there.</p>
  {limits&&<div className="plan-change-summary"><h3>{name} includes</h3><p>{limits.weekly_target_limit} weekly customer targets</p><p>Up to {limits.store_listing_limit} active listings</p>{active!==undefined&&active>limits.store_listing_limit&&<p className="billing-message info">You currently have {active} active listings. This is above the {name} limit; you will need to reduce your active listings before publishing more.</p>}</div>}
  {paidUntil&&<p className="billing-note">Your currently verified access runs through {new Date(paidUntil).toLocaleDateString()}. Check the change date shown in billing.</p>}
  <p className="billing-note">{plan==='free'?'Choose cancellation in billing to return to Free.':`Choose ${name} in billing to review and confirm the change.`} Your past conversations and deal history stay in your account.</p>
  <div className="billing-actions"><button type="button" className="button primary" disabled={busy} onClick={onContinue}>Continue to billing</button><button type="button" className="button secondary" disabled={busy} onClick={onClose}>Keep current plan</button></div>
 </BillingDialog>;
}

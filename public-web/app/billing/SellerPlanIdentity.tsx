import BillingArtwork from './BillingArtwork';
import {planBenefits} from './plan-presentation';
import type {BillingEntitlement} from './SellerBillingOverview';
const names:Record<string,string>={free:'Free',pro:'Pro Seller',elite:'Elite Seller'};
export default function SellerPlanIdentity({plan,entitlement,priceLabel,current=false,primary=false,accessLabel}:{plan:string;entitlement?:BillingEntitlement;priceLabel?:string;current?:boolean;primary?:boolean;accessLabel?:string}){
 const role=plan in names?plan:'free',paid=role!=='free';
 const limits=entitlement?.plans?.find(row=>row.plan_code===role);
 const threshold=entitlement?.policy?.earned_pro_threshold??entitlement?.earned?.threshold;
 const benefits=planBenefits(role,entitlement);
 const compactFreeSummary=!paid&&primary&&Boolean(accessLabel);
 const earnedProBenefit=!paid&&threshold?benefits[limits?2:0]:undefined;
 const Heading=primary?'h1':'h3';
 return <div className={`seller-plan-identity tier-${role}`}>
  <header className="seller-current-plan-heading"><div><p className="plan-kicker">{current?'Current plan':'Seller plan'}</p><Heading>{names[role]}</Heading><div className="plan-current-meta">{priceLabel&&<span>{priceLabel}</span>}{current&&<span className="plan-active">Active</span>}</div></div>{paid&&<BillingArtwork plan={role} crop={[590,230,205,185]} size={primary?96:112}/>}</header>
  <ul className={paid?'plan-benefits':'plan-benefits free-benefits'}>{benefits.map((benefit,i)=>{
   const index=limits?i:i+2;
   const label=compactFreeSummary&&limits&&i===0?`${limits.weekly_target_limit} weekly customers`
     :compactFreeSummary&&limits&&i===1?`Up to ${limits.store_listing_limit} listings`
     :compactFreeSummary&&benefit===earnedProBenefit?`Earn Pro with ${threshold} sales`:benefit;
   return <li key={benefit}><BillingArtwork plan={role} crop={paid?[76,438+index*80,70,68]:[[82,403,115,100],[275,403,115,100],[464,403,115,100],[657,403,115,100]][index] as [number,number,number,number]} size={paid?(primary?30:38):46}/><span>{label}</span></li>;
  })}</ul>
  {accessLabel&&<p className="plan-access-label">{compactFreeSummary&&earnedProBenefit?`${earnedProBenefit}.`:accessLabel}</p>}
 </div>;
}

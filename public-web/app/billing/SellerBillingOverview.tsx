import BillingArtwork from './BillingArtwork';
import SellerPlanIdentity from './SellerPlanIdentity';
export {default as BillingArtwork} from './BillingArtwork';

export type BillingEntitlement={
 effective_source?:string;
 plans?:{plan_code:string;weekly_target_limit:number;store_listing_limit:number}[];
 earned?:{threshold?:number};
 policy?:{earned_pro_threshold?:number};
 store_listing?:{active:number;limit:number};
};
export type StandardRate={plan_code:string;initial_minor:number;winning_minor:number};
type Option={id:string;amount_minor:number;initial_fee_minor:number;winning_total_minor:number};
const names:Record<string,string>={free:'Free',pro:'Pro Seller',elite:'Elite Seller'};
export default function SellerBillingOverview({plan,entitlement,options,standard,priceLabel,accessLabel,onAddCredits,onSelectPlan}:{
 plan:string;entitlement?:BillingEntitlement;options:Option[];standard?:StandardRate;priceLabel?:string;accessLabel:string;onAddCredits:()=>void;onSelectPlan:()=>void;
}){
 const role=['free','pro','elite'].includes(plan)?plan:'free',paid=role!=='free';
 return <>
  <article className={`seller-current-plan tier-${role}`}>
   <SellerPlanIdentity plan={role} entitlement={entitlement} priceLabel={priceLabel} current primary accessLabel={accessLabel}/>
  </article>
  <details open className={`seller-fees tier-${role}`}>
   <summary><span><BillingArtwork crop={[70,1035,50,50]} size={27}/>Targeting fees</span><img className="fees-toggle" src="/billing/chevron.png" alt=""/></summary>
   {standard?<div className="standard-fees"><strong>{paid?`${names[role]} rates`:'Standard rates'}<small>Pay as you go</small></strong><div><span>Winning total</span><b>{(standard.winning_minor/100).toFixed(2)}<small>HC</small></b></div><div><span>Initial fee</span><b>{(standard.initial_minor/100).toFixed(2)}<small>HC</small></b></div></div>:<p className="billing-note">Standard rates will appear when pay-as-you-go billing is available.</p>}
   <div className="wallet-savings"><h2><BillingArtwork crop={[80,1236,50,48]} size={25}/>Prepaid wallet savings</h2>
    {options.length?<table><thead><tr><th scope="col">Wallet</th><th scope="col">Initial fee</th><th scope="col">Winning total</th></tr></thead><tbody>{options.map(option=><tr key={option.id}><th scope="row">{(option.amount_minor/100).toFixed(option.amount_minor%100?2:0)} HC</th><td>{(option.initial_fee_minor/100).toFixed(2)} HC</td><td>{(option.winning_total_minor/100).toFixed(2)} HC</td></tr>)}</tbody></table>:<p className="billing-note">No prepaid options are currently available.</p>}
   </div>
   <p className="fee-explanation">The winning total includes the initial fee. Sending an offer is free. {role==='elite'?'After the buyer replies, Elite fees stay pending until a PIN-confirmed purchase or the seven-day deadline. Eligible sellers owe no initial fee if no purchase is confirmed.':'The buyer’s reply triggers the initial fee for that deal. PIN confirmation triggers only the remaining difference.'}</p>
  </details>
  <div className="wallet-credit-banner"><BillingArtwork plan="free" crop={[68,1165,130,130]} size={54}/><div><span>Wallet credits</span><p>Add credits to save on targeting fees.</p></div><button type="button" onClick={onAddCredits}>Add credits <img className="billing-forward" src="/billing/chevron.png" alt=""/></button></div>
  <button className="plan-choose-banner" type="button" onClick={onSelectPlan}><span><strong>{paid?'Compare seller plans':'Explore Pro Seller'}</strong><small>Choose the plan that fits your needs.</small></span><img className="billing-forward" src="/billing/chevron.png" alt=""/></button>
 </>;
}

import type {BillingEntitlement} from './SellerBillingOverview';

export function planBenefits(plan:string,entitlement?:BillingEntitlement):string[]{
 const limits=entitlement?.plans?.find(row=>row.plan_code===plan);
 const benefits=limits?[`Target up to ${limits.weekly_target_limit} weekly customers`,`List up to ${limits.store_listing_limit} products or services`]:[];
 const threshold=entitlement?.policy?.earned_pro_threshold??entitlement?.earned?.threshold;
 if(plan==='free') return [...benefits,threshold?`${threshold} PIN-confirmed sales this month unlock Pro next month`:'Earn Pro seller benefits','Seller storefront'];
 return [...benefits,'Offer withdrawal before the buyer responds','Contacts dashboard','Recommended leads','Get listed on Hocatrends','More savings on targeting fees',...(plan==='elite'?['Refunds when no purchase is confirmed','View competing offers after buyer acceptance','Customer insights']:[])];
}

export function isCurrentPlan(active:boolean,currentPlan:string,currentInterval:string|undefined,plan:string,interval:string):boolean{
 return active&&currentPlan===plan&&currentInterval===interval;
}

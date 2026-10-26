import BillingArtwork from './BillingArtwork';
export default function PlanSelectionAction({plan,label,disabled,onClick}:{plan:string;label:string;disabled:boolean;onClick:()=>void}){
 const elite=plan==='elite';
 return <div className={`plan-selection-action ${elite?'elite-plan-action':'standard-plan-action'}`}>
  {elite?<button className="button primary" type="button" disabled={disabled} onClick={onClick}><BillingArtwork plan="elite" crop={[82,1740,58,58]} size={30}/><span>{label}</span><img className="billing-forward" src="/billing/chevron.png" alt=""/></button>:
   <div className="plan-selection-bar"><BillingArtwork plan="pro" crop={[66,1508,100,100]} size={46}/><div className="plan-selection-caption"><span>Select plan</span><small>Choose what fits your needs.</small></div><button className="button primary" type="button" disabled={disabled} onClick={onClick}><span>{label}</span><img className="billing-forward" src="/billing/chevron.png" alt=""/></button></div>}
 </div>;
}

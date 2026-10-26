import BillingArtwork from './BillingArtwork';
export type PlanFeeRates={plan_code:string;initial_minor:number;winning_minor:number;deposits:{amount_minor:number;initial_fee_minor:number;winning_total_minor:number}[]};
const names:Record<string,string>={free:'Standard fees',pro:'Pro Seller rates',elite:'Elite Seller rates'};
export default function PlanTargetingFees({rates}:{rates?:PlanFeeRates}){
 const role=rates?.plan_code??'free',elite=role==='elite';
 return <details className={`seller-fees comparison-targeting-fees tier-${role}`}><summary><span><BillingArtwork plan={elite?'elite':'pro'} crop={elite?[61,1273,59,59]:[70,1035,50,50]} size={27}/>Targeting fees</span><img className="fees-toggle" src="/billing/chevron.png" alt=""/></summary>
  {rates?<>
   <div className="standard-fees"><strong>{names[role]}<small>Standard rates</small></strong><div><span>Winning total</span><b>{(rates.winning_minor/100).toFixed(2)}<small>HC</small></b></div><div><span>Initial fee</span><b>{(rates.initial_minor/100).toFixed(2)}<small>HC</small></b></div></div>
   <div className="wallet-savings"><h2><BillingArtwork plan={elite?'elite':'pro'} crop={elite?[83,1473,49,47]:[80,1236,50,48]} size={25}/>Prepaid wallet savings</h2>
   {rates.deposits.length?<table><thead><tr><th scope="col">Wallet</th><th scope="col">Initial fee</th><th scope="col">Winning total</th></tr></thead><tbody>{rates.deposits.map(row=><tr key={row.amount_minor}><th scope="row">{row.amount_minor/100} HC</th><td>{(row.initial_fee_minor/100).toFixed(2)} HC</td><td>{(row.winning_total_minor/100).toFixed(2)} HC</td></tr>)}</tbody></table>:<p>Prepaid rates are not available yet.</p>}</div>
   <p className="fee-explanation">The winning total includes the initial fee. Initial fees apply after the buyer replies; PIN confirmation triggers the remaining difference.</p>
  </>:<p className="billing-note">This plan’s targeting rates are not available right now.</p>}
 </details>;
}

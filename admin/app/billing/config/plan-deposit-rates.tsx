"use client";
import {useState} from "react";
import {FieldHelp} from "../../field-help";
import {formatMinorInput,parseMinorAmount,type PlanDepositRate} from "../../lib/admin-commercial";

export function PlanDepositRates({rows,busy,onSave,prepaid=true}:{rows:PlanDepositRate[];busy:boolean;onSave:(input:Record<string,unknown>)=>Promise<void>;prepaid?:boolean}) {
 const [editing,setEditing]=useState<PlanDepositRate|null>(null);
 const [initial,setInitial]=useState("");
 const [winning,setWinning]=useState("");
 const [error,setError]=useState<string|null>(null);
 const stale=editing!==null && rows.find(r=>r.plan_code===editing.plan_code && r.amount_minor===editing.amount_minor)?.revision!==editing.revision;
 return <section className="table-card">
  <h2>{prepaid?'Fees by seller plan':'Pay-as-you-go rates'} <FieldHelp label={prepaid?'Fees by seller plan':'Pay-as-you-go rates'}>{prepaid?'These fees apply to new credit deposits. The winning total includes the initial fee. Past deposits keep their original rates.':'These standard fees apply to future pay-as-you-go deals. The initial fee is due after the buyer replies. The winning total includes that initial fee; only the remaining difference is due after PIN confirmation. Existing deals keep their saved rates. Saving rates does not enable card charging.'}</FieldHelp></h2>
  <div className="table-scroll"><table><thead><tr><th>Plan</th>{prepaid&&<th>Deposit</th>}<th>Initial fee</th><th>Winning total</th><th>Action</th></tr></thead><tbody>
   {rows.map(r=><tr key={`${r.plan_code}:${r.amount_minor}`}><td>{r.plan_code}</td>{prepaid&&<td>{formatMinorInput(r.amount_minor)} HC</td>}<td>{formatMinorInput(r.initial_fee_minor)} HC</td><td>{formatMinorInput(r.winning_total_minor)} HC</td><td><button className="row-action" disabled={busy} onClick={()=>{setEditing(r);setInitial(formatMinorInput(r.initial_fee_minor));setWinning(formatMinorInput(r.winning_total_minor));setError(null);}}>Edit</button></td></tr>)}
  </tbody></table></div>
  {editing && <form className="form-grid" onSubmit={async e=>{
   e.preventDefault();if(busy||stale)return;
   const a=parseMinorAmount(initial),b=parseMinorAmount(winning);
   if(a===null||b===null||b<a||(prepaid?b>editing.amount_minor:a<50||(b!==a&&b-a<50))){setError(prepaid?"Enter valid HC fees. The winning total must include the initial fee and fit within the deposit.":"Enter valid HC fees. Each card charge must be at least 0.50 HC, and the winning total must include the initial fee.");return;}
   await onSave(prepaid?{plan_code:editing.plan_code,amount_minor:editing.amount_minor,initial_fee_minor:a,winning_total_minor:b,rate_version:editing.rate_version,expected_revision:editing.revision}:{plan_code:editing.plan_code,initial_minor:a,winning_minor:b,expected_revision:editing.revision});
  }}>
   <p>Editing {editing.plan_code}{prepaid?`, ${formatMinorInput(editing.amount_minor)} HC deposit`:''}</p>
   {stale&&<p role="alert">This rate changed. Select Edit again to load its current values.</p>}
   {error&&<p role="alert">{error}</p>}
   <label>Initial fee (HC)<input inputMode="decimal" maxLength={16} value={initial} disabled={busy||stale} onChange={e=>setInitial(e.target.value)}/></label>
   <label>Winning total (HC)<input inputMode="decimal" maxLength={16} value={winning} disabled={busy||stale} onChange={e=>setWinning(e.target.value)}/></label>
   <div className="form-actions"><button disabled={busy||stale}>Save rate</button><button type="button" disabled={busy} onClick={()=>setEditing(null)}>Cancel</button></div>
  </form>}
 </section>;
}

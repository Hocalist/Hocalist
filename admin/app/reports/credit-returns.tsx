"use client";
import {useEffect,useRef,useState} from 'react';
import {adminRpc} from '../lib/admin-client';
import {decodeReportCreditTargets,type ReportCreditTarget} from '../lib/admin-credit-returns';
import {FieldHelp} from '../field-help';
export function ReportCreditReturns({caseId,resolved}:{caseId:string;resolved:boolean}){
 const [rows,setRows]=useState<ReportCreditTarget[]>([]),[target,setTarget]=useState(''),[reason,setReason]=useState('');
 const [busy,setBusy]=useState(false),[message,setMessage]=useState<string|null>(null);
 const generation=useRef(0),inFlight=useRef(false);
 useEffect(()=>{const token=++generation.current;setRows([]);setTarget('');setReason('');setMessage(null);
  void adminRpc('admin_report_credit_targets',{p_case:caseId}).then(r=>{
   if(token!==generation.current)return;
   const data=r.ok?decodeReportCreditTargets(r.data):null;
   if(data)setRows(data);else setMessage('Eligible targeting fees could not be loaded.');
  });return()=>{generation.current++;};
 },[caseId]);
 async function submit(){
  if(inFlight.current||!resolved||!target||reason.trim().length<10)return;
  const token=generation.current;inFlight.current=true;setBusy(true);setMessage(null);
  try{
   const result=await adminRpc('admin_report_credit_return',{p_case:caseId,p_target:target,p_reason:reason.trim()});
   if(token!==generation.current)return;
   if(!result.ok){setMessage('The return was not confirmed. Check the misconduct review and retry the same details.');return;}
   setRows(current=>current.map(r=>r.id===target?{...r,returned:true}:r));
   setMessage('The charged credits were returned to the original wallet.');
  }finally{inFlight.current=false;if(token===generation.current)setBusy(false);}
 }
 return <section className="table-card"><h3>Return targeting credits <FieldHelp label="Return targeting credits">Resolve the report and record a misconduct decision in Account health first. This returns only a real charged fee from an unconfirmed deal. It cannot create extra credits or refund a completed purchase.</FieldHelp></h3>
  {!rows.length?<p>No eligible charged fees for this report.</p>:<>
   <label>Deal<select value={target} disabled={busy||!resolved} onChange={e=>setTarget(e.target.value)}><option value="">Choose a deal</option>{rows.map(r=><option key={r.id} value={r.id} disabled={r.returned}>{r.title} · {(r.fee_minor/100).toFixed(2)} HC{r.returned?' · Returned':''}</option>)}</select></label>
   <label>Reason for returning credits<textarea value={reason} minLength={10} maxLength={500} disabled={busy||!resolved} onChange={e=>setReason(e.target.value)}/></label>
   <button type="button" className="primary" disabled={busy||!resolved||!target||reason.trim().length<10||rows.find(r=>r.id===target)?.returned} onClick={()=>void submit()}>{busy?'Returning credits…':'Return charged credits'}</button>
  </>}
  {message&&<p role="status">{message}</p>}
  {!resolved&&<p>Resolve the report before returning credits.</p>}
 </section>;
}

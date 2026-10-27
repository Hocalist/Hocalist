'use client';
import {useEffect,useId,useRef,useState} from 'react';
import {verifyPaygoBankPayment} from './paygo-bank-verification';
import BillingLoading from './BillingLoading';
import {paygoReturn} from './paygo-return';
type Charge={id:string;phase:string;request_title:string;fee_minor:number;amount_minor:number;state:string};
function chargesFrom(value:unknown):Charge[]{
 if(!Array.isArray(value))return [];
 return value.slice(0,20).filter((v):v is Charge=>v&&typeof v.id==='string'&&typeof v.request_title==='string'&&typeof v.phase==='string'&&Number.isSafeInteger(v.fee_minor)&&Number.isSafeInteger(v.amount_minor)&&v.fee_minor>=0&&v.amount_minor>=0&&typeof v.state==='string');
}

// Uses the existing billing card/button styles. Hidden until both server-side
// setup and the payment-collection release gate are explicitly enabled.
export default function PaygoPaymentSetup({preview=false,setupOnly=false,onManage}:{preview?:boolean;setupOnly?:boolean;onManage?:()=>void}) {
 const headingId=useId();
 const [available,setAvailable]=useState<boolean|null>(preview?true:null),[authorised,setAuthorised]=useState(preview&&!setupOnly);
 const [consent,setConsent]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 const [charges,setCharges]=useState<Charge[]>([]);
 const key=useRef<string|null>(null);
 useEffect(()=>{
  if(preview)return;let active=true;
  async function load(){try{
   const response=await fetch('/api/billing/paygo',{cache:'no-store'}),body=await response.json();
   if(!active)return;
   if(!response.ok||body.state!=='ready'){setAvailable(false);return;}
   setAvailable(true);setAuthorised(body.authorised===true);setCharges(chargesFrom(body.charges));
   const returned=paygoReturn(new URL(window.location.href).searchParams);
   const setup=returned.setupId;
   if(setupOnly&&returned.cancelled){
    setMessage('Card setup was cancelled. You can try again when ready.');
    const clean=new URL(window.location.href);clean.searchParams.delete('paygo_cancelled');window.history.replaceState(null,'',clean);
   }
   if(setupOnly&&setup){
    const confirmed=await fetch('/api/billing/paygo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:'confirm',setup_id:setup})});
    const result=await confirmed.json();if(!active)return;
    if(confirmed.ok&&result.state==='authorised'){
     setAuthorised(true);setMessage('Your card is ready for pay as you go. Saving it did not charge it.');
     const clean=new URL(window.location.href);clean.searchParams.delete('paygo_setup');window.history.replaceState(null,'',clean);
    }else setMessage(result.state==='pending'?'Your card setup is not complete yet. Finish it in Stripe, then return here.':'Payment setup could not be confirmed. You can try again.');
   }
  }catch{if(active)setAvailable(false);}}
  void load();return()=>{active=false;};
 },[preview,setupOnly]);
 async function act(){
  if(preview){setMessage('This is a design preview. No payment permission was changed.');return;}
  if(busy||!consent)return;
  setBusy(true);setMessage('');
  try{
   key.current??=crypto.randomUUID();
   const response=await fetch('/api/billing/paygo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:'begin',consent_version:'paygo-v1',idempotency_key:key.current})});
   const body=await response.json();
   if(!response.ok){if(body.code==='setup_expired')key.current=null;throw new Error(body.message??'Payment permission could not be updated. Please try again.');}
   if(body.state==='needs_confirmation'&&typeof body.setup_id==='string'){
    const confirmed=await fetch('/api/billing/paygo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:'confirm',setup_id:body.setup_id})});
    const result=await confirmed.json();if(!confirmed.ok||result.state!=='authorised')throw new Error('Payment setup could not be confirmed. Please try again.');
    setAuthorised(true);setMessage('Your card is ready for pay as you go. Saving it did not charge it.');key.current=null;
   }
   else if(typeof body.url==='string'&&new URL(body.url).origin==='https://checkout.stripe.com')window.location.assign(body.url);
   else throw new Error('The payment setup link could not be verified.');
  }catch(error){setMessage(error instanceof Error?error.message:'Payment setup is unavailable. Please try again.');}
  finally{setBusy(false);}
 }
 async function recover(charge:Charge,operation:'verify'|'retry'|'refresh'){
  if(preview){setMessage('This is a design preview. No payment was started or changed.');return;}
  if(busy)return;setBusy(true);setMessage('');
  const post=async(op:string)=>{
   const response=await fetch('/api/billing/paygo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:op,charge_id:charge.id})});
   const body=await response.json();if(!response.ok)throw new Error(body.message??'This payment could not be updated. Please try again.');return body;
  };
  try{
   let result=await post(operation);
   if(operation==='verify'&&result.state==='requires_action'){
    await verifyPaygoBankPayment(result.publishable_key,result.client_secret);
    result=await post('refresh');
   }else if(result.state==='needs_refresh')result=await post('refresh');
   setMessage(result.state==='succeeded'?'Your payment is confirmed.':result.state==='requires_action'?'Your bank needs to verify this payment. Choose Approve payment.':result.state==='requires_payment_method'?'Your card was declined. Use Manage payment to update it, then retry.':'This payment is still being checked. Please do not pay again.');
   const response=await fetch('/api/billing/paygo',{cache:'no-store'}),body=await response.json();
   if(response.ok){setCharges(chargesFrom(body.charges));setAuthorised(body.authorised===true);}
  }catch(error){setMessage(error instanceof Error?error.message:'Payment verification is unavailable.');}
  finally{setBusy(false);}
 }
 if(available===null)return setupOnly?<BillingLoading label="Checking card setup…"/>:null;
 if(!available)return setupOnly?<p className="billing-message info" role="status">Card setup is not available right now. Please try again later.</p>:null;
 if(!setupOnly&&charges.length===0)return null;
 return <section className="billing-paygo" aria-labelledby={headingId}>
  {setupOnly&&<><p className="eyebrow">Pay as you go</p><h2 id={headingId}>{authorised?'Your card is ready':'Save a card for targeting fees'}</h2>
  <p>Sending an offer does not charge the initial fee. For Free and Pro, it applies when the buyer replies in that deal’s conversation. Elite fees stay pending until a PIN-confirmed purchase or the seven-day deadline, with eligible no-purchase fees waived. The winning total includes the initial fee. Your plan’s rates apply to each deal.</p>
  {authorised?<><p>Use Manage payment to change your card or update its details.</p><button className="button secondary" disabled={busy||!onManage} onClick={onManage}>Manage payment</button></>:<>
   <label className="billing-consent"><input type="checkbox" checked={consent} disabled={busy} onChange={e=>setConsent(e.target.checked)}/> I authorise these future targeting charges. Saving my card does not charge it.</label>
   <button className="button" disabled={!consent||busy} onClick={()=>void act()}>{busy?'Opening secure setup…':'Save card securely'}</button>
  </>}
  </>}
  {!setupOnly&&charges.length?<div className="billing-paygo-payments"><h3 id={headingId}>{charges.some(charge=>['requires_action','requires_payment_method','review'].includes(charge.state))?'Payments needing attention':'Payment processing'}</h3><ul className="billing-history">{charges.map(charge=><li key={charge.id}>
   <div><strong>{charge.request_title}</strong><span>{charge.phase==='initial'?'Initial targeting fee':'Remaining winning fee'} · {(charge.fee_minor/100).toFixed(2)} HC</span><span>{charge.amount_minor===0?'Covered by returned credits':`Card payment: $${(charge.amount_minor/100).toFixed(2)}`}</span></div>
   <div><p>{charge.state==='requires_action'?'Your bank needs to approve this payment.':charge.state==='requires_payment_method'?'Your card was declined. Update it in Manage payment, or retry.':charge.state==='review'?'Contact support about this payment.':'Payment confirmation is pending.'}</p>
   {charge.state==='requires_action'?<button className="button secondary small" disabled={busy} onClick={()=>void recover(charge,'verify')}>Approve payment</button>:charge.state==='requires_payment_method'?<><button className="button secondary small" disabled={busy||!onManage} onClick={onManage}>Manage payment</button><button className="button secondary small" disabled={busy||!authorised} onClick={()=>void recover(charge,'retry')}>Retry payment</button></>:charge.state!=='review'?<button className="button secondary small" disabled={busy} onClick={()=>void recover(charge,'refresh')}>Check payment</button>:null}</div>
  </li>)}</ul></div>:null}
  {message?<p className="billing-message info" role="status">{message}</p>:null}
 </section>;
}

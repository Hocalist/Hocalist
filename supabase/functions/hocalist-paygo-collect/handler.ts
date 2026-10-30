import {assertAccount,type Backend,BillingError,boundedBody,failure,id,json,object,uuid} from '../_shared/stripe-test-billing.ts';

// Trusted worker only. There is no customer token or browser charge command.
export function createPaygoCollectionHandler(api:Backend,config:{enabled:boolean;authorise:(request:Request)=>boolean}){
 return async(request:Request):Promise<Response>=>{
  if(request.method!=='POST')return json({error:'method_not_allowed'},405);
  if(!config.enabled)return json({error:'billing_unavailable'},503);
  if(!config.authorise(request))return json({error:'access_denied'},403);
  try{
   const body=await boundedBody(request);
   if(Object.keys(body).length!==0&&Object.keys(body).join(',')!=='charge_id')throw new BillingError('invalid_request',400);
   await assertAccount(api);
   let selected=body.charge_id;
   if(selected===undefined){const next=await api.rpc('paygo_next_charge');if(next===null)return json({state:'idle'});selected=object(next).id;}
   const charge=uuid(selected);
   const job=object(await api.rpc('paygo_charge_context',{p_charge:charge}));
   if(['succeeded','canceled','review','waiting_for_initial'].includes(String(job.state)))return json({state:job.state});
   const amount=Number(job.amount_minor);
   if(amount===0&&Number(job.fee_minor)>0&&job.payment_intent_id==null){
    await api.rpc('paygo_charge_finish',{p_charge:charge,p_intent:null,p_customer:job.customer_id,p_amount:0,p_state:'succeeded'});
    return json({state:'succeeded'});
   }
   if(!Number.isSafeInteger(amount)||amount<50||!/^cus_[A-Za-z0-9]+$/.test(String(job.customer_id))||!/^pm_[A-Za-z0-9]+$/.test(String(job.payment_method_id)))throw new Error('review_required');
   let intent;
   if(job.payment_intent_id){
    intent=await api.stripe(`payment_intents/${encodeURIComponent(String(job.payment_intent_id))}`);
   }else{
    // A missing response after the provider's 24-hour idempotency retention
    // must go to review, never create another charge with an expired key.
    if(!job.may_confirm||!Number.isFinite(Date.parse(String(job.created_at)))||Date.now()-Date.parse(String(job.created_at))>23*60*60*1000)throw new Error('review_required');
    intent=await api.stripe('payment_intents',{
     amount:String(amount),currency:'usd',customer:String(job.customer_id),payment_method:String(job.payment_method_id),
     'payment_method_types[0]':'card','metadata[app]':'hocalist','metadata[kind]':'paygo_targeting',
     'metadata[charge_id]':charge,'metadata[target_id]':String(job.target_id),'metadata[phase]':String(job.phase),
     description:'Hocalist targeting fee',
    },`hocalist-paygo-create-${charge}`);
    verify(intent,job,charge,amount);
    await api.rpc('paygo_charge_bind',{p_charge:charge,p_intent:id(intent)});
   }
   const retry=Number(job.retry_generation??0);
   const updateRetry=retry>0&&job.state==='pending'&&['requires_payment_method','requires_confirmation'].includes(String(intent.status));
   verify(intent,job,charge,amount,updateRetry);
   if(updateRetry){
    intent=await api.stripe(`payment_intents/${encodeURIComponent(id(intent))}`,{payment_method:String(job.payment_method_id)},`hocalist-paygo-method-${charge}-${retry}`);
    verify(intent,job,charge,amount);
   }
   if(intent.status==='requires_confirmation'||(updateRetry&&intent.status==='requires_payment_method')){
    // Recheck permission after binding, immediately before confirmation.
    const latest=object(await api.rpc('paygo_charge_context',{p_charge:charge}));
    if(latest.may_confirm===true){
     try{await api.stripe(`payment_intents/${encodeURIComponent(id(intent))}/confirm`,{off_session:'true'},`hocalist-paygo-confirm-${charge}-${retry}`);}catch{/* A decline or lost response is resolved by retrieval below. */}
    }else{
     try{await api.stripe(`payment_intents/${encodeURIComponent(id(intent))}/cancel`,{},`hocalist-paygo-cancel-${charge}`);}catch{/* Reconcile the provider result; never assume cancellation. */}
    }
    intent=await api.stripe(`payment_intents/${encodeURIComponent(id(intent))}`);verify(intent,job,charge,amount);
   }
   const states:Record<string,string>={succeeded:'succeeded',requires_action:'requires_action',requires_payment_method:'requires_payment_method',processing:'processing',canceled:'canceled',requires_confirmation:'pending'};
   const state=states[String(intent.status)]??'review';
   if(state==='succeeded'&&intent.amount_received!==amount)throw new Error('review_required');
   await api.rpc('paygo_charge_finish',{p_charge:charge,p_intent:id(intent),p_customer:job.customer_id,p_amount:amount,p_state:state});
   return json({state});
  }catch(error){return failure(error);}
 };
}
function verify(intent:Record<string,unknown>,job:Record<string,unknown>,charge:string,amount:number,allowMethodUpdate=false){
 const metadata=object(intent.metadata);
 // Stripe clears payment_method after some declines. Its verified error
 // retains the attempted method; accept that identity only for this state.
 const declinedMethod=intent.status==='requires_payment_method'&&intent.payment_method==null
  ? (intent.last_payment_error as Record<string,unknown>|null)?.payment_method : null;
 const method=intent.payment_method??declinedMethod;
 if(!/^pi_[A-Za-z0-9]+$/.test(id(intent))||(job.payment_intent_id&&id(intent)!==job.payment_intent_id)||intent.livemode!==false||id(intent.customer)!==job.customer_id||(!allowMethodUpdate&&id(method)!==job.payment_method_id)||intent.amount!==amount||intent.currency!=='usd'||metadata.app!=='hocalist'||metadata.kind!=='paygo_targeting'||metadata.charge_id!==charge||metadata.target_id!==job.target_id||metadata.phase!==job.phase)throw new Error('review_required');
}

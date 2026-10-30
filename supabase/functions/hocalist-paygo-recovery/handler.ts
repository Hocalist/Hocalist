import {assertAccount,type Backend,BillingError,boundedBody,failure,id,json,object,uuid} from '../_shared/stripe-test-billing.ts';
import {createPaygoCollectionHandler} from '../hocalist-paygo-collect/handler.ts';
import {refreshManagedPaygoCard} from '../_shared/paygo-managed-card.ts';
export function createPaygoRecoveryHandler(api:Backend,config:{enabled:boolean;publishableKey:string}){
 return async(request:Request):Promise<Response>=>{
  if(request.method!=='POST')return json({error:'method_not_allowed'},405);
  if(!config.enabled)return json({error:'billing_unavailable'},503);
  try{
   const user=await api.user(request),body=await boundedBody(request);
   if(Object.keys(body).sort().join(',')!=='charge_id,operation'||!['verify','refresh','retry'].includes(String(body.operation)))throw new BillingError('invalid_request',400);
   const charge=uuid(body.charge_id);await assertAccount(api);
   let job=object(await api.rpc('paygo_charge_for_user',{p_user:user,p_charge:charge}));
   if(body.operation==='retry'){
    await refreshManagedPaygoCard(api,user);
    await api.rpc('paygo_charge_retry',{p_user:user,p_charge:charge});
    job=object(await api.rpc('paygo_charge_for_user',{p_user:user,p_charge:charge}));
   }
   if(body.operation==='verify'){
    if(job.state!=='requires_action'||!job.payment_intent_id||!/^pk_test_[A-Za-z0-9]+$/.test(config.publishableKey))throw new BillingError('verification_unavailable',409);
    const intent=await api.stripe(`payment_intents/${encodeURIComponent(String(job.payment_intent_id))}`),metadata=object(intent.metadata);
    if(id(intent)!==job.payment_intent_id||intent.livemode!==false||id(intent.customer)!==job.customer_id||intent.amount!==Number(job.amount_minor)||intent.currency!=='usd'||metadata.app!=='hocalist'||metadata.kind!=='paygo_targeting'||metadata.charge_id!==charge||metadata.target_id!==job.target_id||metadata.phase!==job.phase)throw new Error('review_required');
    if(intent.status!=='requires_action')return json({state:'needs_refresh'});
    if(typeof intent.client_secret!=='string'||!intent.client_secret.startsWith(`${job.payment_intent_id}_secret_`))throw new Error('review_required');
    // Only the authenticated charge owner receives this short-lived browser
    // capability. It is never put into an address, receipt or persisted log.
    return json({state:'requires_action',client_secret:intent.client_secret,publishable_key:config.publishableKey});
   }
   if(!job.payment_intent_id)return json({state:job.state});
   // This internal call is reachable only after the charge ownership check.
   return createPaygoCollectionHandler(api,{enabled:true,authorise:()=>true})(new Request('https://internal.invalid/collect',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({charge_id:charge})}));
  }catch(error){return failure(error);}
 };
}

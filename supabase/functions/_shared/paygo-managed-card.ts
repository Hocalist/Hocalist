import {type Backend,id,object} from './stripe-test-billing.ts';

// Provider-verified card refresh under existing consent. Never accepts a
// customer/card identity from the browser and never confirms a payment.
export async function refreshManagedPaygoCard(api:Backend,user:string):Promise<void>{
 const raw=await api.rpc('paygo_card_context',{p_user:user});
 if(raw===null)return;
 const context=object(raw),customerId=String(context.customer_id);
 if(!/^cus_[A-Za-z0-9]+$/.test(customerId))throw new Error('review_required');
 const customer=await api.stripe(`customers/${customerId}`);
 if(id(customer)!==customerId||customer.deleted===true||customer.livemode!==false)throw new Error('review_required');
 const defaultMethod=object(customer.invoice_settings??{}).default_payment_method;
 const methodId=defaultMethod? id(defaultMethod):String(context.payment_method_id);
 if(!/^pm_[A-Za-z0-9]+$/.test(methodId))throw new Error('review_required');
 const method=await api.stripe(`payment_methods/${methodId}`);
 if(id(method)!==methodId||method.livemode!==false||method.type!=='card'||id(method.customer)!==customerId)throw new Error('review_required');
 await api.rpc('paygo_card_refresh',{p_user:user,p_customer:customerId,p_previous:context.payment_method_id,p_method:methodId});
}

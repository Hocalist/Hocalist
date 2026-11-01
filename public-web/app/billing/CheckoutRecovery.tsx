import type {CheckoutIntent, CheckoutRow} from '../lib/website-checkout';

export default function CheckoutRecovery({checkout,retained,busy,onContinue,onCancel}:{
  checkout?:CheckoutRow|null;retained:CheckoutIntent|null;busy:boolean;
  onContinue:(kind:CheckoutIntent['kind'],value:string)=>void;onCancel:(id:string)=>void;
}) {
  if (!checkout && !retained) return null;
  const choice = retained ?? (checkout?.kind==='subscription' && checkout.plan_code
    ? {kind:'subscription' as const,value:`${checkout.plan_code}:${checkout.billing_interval ?? 'month'}`}
    : checkout?.kind==='credit_deposit' && (checkout.option_id || checkout.standard_deposit)
    ? {kind:'credit_deposit' as const,value:checkout.standard_deposit?`standard:${checkout.amount_minor}`:checkout.option_id!}
    : null);
  return <div className="billing-message info" role="status">
    <strong>Unfinished purchase</strong>
    <p>Continue your previous purchase before starting another. No new payment is taken by reopening it.</p>
    {choice ? <button className="button secondary" type="button" disabled={busy}
      onClick={()=>onContinue(choice.kind,choice.value)}>Continue previous checkout</button>:null}
    {checkout?.state==='open' ? <button className="button secondary" type="button" disabled={busy}
      onClick={()=>onCancel(checkout.id)}>Cancel unpaid checkout</button>:
      <p>Continue the previous checkout to recover its payment status. If payment is still being confirmed, wait for confirmation before choosing another pack.</p>}
  </div>;
}

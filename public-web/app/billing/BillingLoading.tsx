export default function BillingLoading({label}: {label:string}) {
  return <div className="billing-brand-loading" role="status" aria-busy="true">
    <img src="/brand/hocalist-icon.png" width="32" height="40" alt="" className="billing-loading-mark" />
    <span>{label}</span>
  </div>;
}

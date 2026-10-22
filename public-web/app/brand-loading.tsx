export function BrandLoading({ label = 'Opening Hocalist…' }: { label?: string }) {
  return <div className="brand-loading" role="status" aria-live="polite">
    <img src="/brand/hocalist-icon.png" width="80" height="80" alt="" />
    <p>{label}</p>
  </div>;
}

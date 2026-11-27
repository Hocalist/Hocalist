export function sellerPlanChoice(params: URLSearchParams) {
  const plan = params.get('plan');
  return plan === 'free' || plan === 'pro' || plan === 'elite' ? plan : null;
}

export function sellerBillingPath(params: URLSearchParams) {
  const plan = sellerPlanChoice(params);
  return plan ? `/billing?plan=${plan}#seller-plans` : '/billing';
}

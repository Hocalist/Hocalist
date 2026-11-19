export async function closeUnpaidCheckout(checkoutId: string) {
  const response = await fetch('/api/billing/checkout', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ kind: 'cancel', checkoutId }),
  });
  const body = await response.json();
  if (!response.ok || body.cancelled !== true || body.checkoutId !== checkoutId) {
    throw new Error(body.message || 'Could not confirm the checkout status. Please try again.');
  }
}

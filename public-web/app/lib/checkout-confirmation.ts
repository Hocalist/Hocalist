// Keep confirming a pending purchase until authoritative state changes.
// Hidden tabs poll less often; neither elapsed time nor a URL implies payment.
export function confirmationDelay(pending: boolean, hidden: boolean): number | null {
  return pending ? hidden ? 30_000 : 5_000 : null;
}

export const confirmationCopy = {
  title: 'Confirming your payment',
  body: 'We’re checking your purchase securely. Your credits or plan will appear automatically once confirmation is complete. You can leave this page and return later.',
  delayed: 'This is taking longer than usual. We’re still checking. Please don’t pay again for this purchase. If it remains pending, contact support.',
};

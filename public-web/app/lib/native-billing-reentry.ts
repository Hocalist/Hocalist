/** Reopening a native billing intent may reuse the browser's existing page.
 * A fragment-only navigation does not remount React: reload that admission
 * document so its existing one-use-ticket flow can run with the new ticket.
 * This listener never reads session storage, redeems tickets or changes auth.
 */
export function subscribeNativeBillingReentry(
  target: {
    addEventListener(type: string, listener: EventListener): void;
    removeEventListener(type: string, listener: EventListener): void;
  },
  readHash: () => string,
  reload: () => void,
): () => void {
  let reloading = false;
  const changed: EventListener = () => {
    const ticket = new URLSearchParams(readHash().replace(/^#/, '')).get('ticket');
    if (reloading || !ticket || !/^[A-Za-z0-9_-]{50,8192}$/.test(ticket)) return;
    reloading = true;
    reload();
  };
  target.addEventListener('hashchange', changed);
  return () => target.removeEventListener('hashchange', changed);
}

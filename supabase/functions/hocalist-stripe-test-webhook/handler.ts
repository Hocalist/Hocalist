import Stripe from 'npm:stripe@22.6.2';

export const account = 'acct_1Le6hqDmHEV44E5Y';
const types = new Set([
  'checkout.session.completed', 'checkout.session.async_payment_succeeded',
  'checkout.session.async_payment_failed', 'customer.subscription.created',
  'customer.subscription.updated', 'customer.subscription.deleted',
  'invoice.paid', 'invoice.payment_failed', 'charge.refunded',
  'charge.dispute.created', 'charge.dispute.closed',
]);
export type Receipt = {
  p_account: string; p_event_id: string; p_type: string;
  p_object_id: string; p_created: number; p_livemode: false;
};
const reply = (status: number, value: string) => new Response(value, {
  status, headers: { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' },
});

export function createHandler(options: {
  signingSecret: string;
  receive: (receipt: Receipt) => Promise<void>;
}) {
  // Signature verification requires no Stripe API key or network request.
  const stripe = new Stripe('sk_test_unused_signature_verification_only');
  return async (request: Request): Promise<Response> => {
    if (request.method !== 'POST') return reply(405, 'method not allowed');
    if (!options.signingSecret.startsWith('whsec_')) return reply(503, 'configuration unavailable');
    const signature = request.headers.get('stripe-signature');
    if (!signature) return reply(400, 'invalid signature');
    // Enforce the limit while streaming; Content-Length is untrusted/optional.
    const reader = request.body?.getReader();
    if (!reader) return reply(400, 'missing body');
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      while (true) {
        const {value, done} = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 262144) { await reader.cancel(); return reply(413, 'payload too large'); }
        chunks.push(value);
      }
    } catch { return reply(400, 'invalid body'); }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        new TextDecoder('utf-8', {fatal:true}).decode(bytes), signature,
        options.signingSecret, 300, Stripe.createSubtleCryptoProvider(),
      );
    } catch { return reply(400, 'invalid signature'); }
    if (!event || typeof event !== 'object' || event.livemode !== false || (event.account && event.account !== account)) {
      return reply(400, 'wrong account or mode');
    }
    if (!types.has(event.type)) return reply(200, 'ignored');
    const object = event.data?.object as {id?: unknown; livemode?: unknown} | undefined;
    if (!/^evt_[A-Za-z0-9]+$/.test(event.id) || !Number.isSafeInteger(event.created) || event.created<=0 ||
      typeof object?.id !== 'string' || object.id.length<3 || object.id.length>255 || object.livemode === true) {
      return reply(400, 'invalid event');
    }
    try {
      await options.receive({p_account:account,p_event_id:event.id,p_type:event.type,
        p_object_id:object.id,p_created:event.created,p_livemode:false});
    } catch { return reply(503, 'receipt unavailable'); }
    // Acknowledge only after durable insert. Processing is a separate worker.
    return reply(200, 'received');
  };
}

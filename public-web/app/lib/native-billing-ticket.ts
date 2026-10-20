import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

export type NativeBillingTicket = { token: string; user: string; nonce: string; expires: number };
function key(): Buffer {
  const value = process.env.HOCALIST_NATIVE_BILLING_KEY ?? '';
  if (!/^[a-f0-9]{64}$/i.test(value)) throw new Error('native_billing_unconfigured');
  return Buffer.from(value, 'hex');
}
export const receiptDigest = (nonce: string) => createHash('sha256').update(nonce).digest('hex');
export function sealNativeBillingTicket(token: string, user: string, now = Date.now()): { ticket: string; receipt: NativeBillingTicket } {
  const receipt = { token, user, nonce: randomBytes(32).toString('hex'), expires: now + 90_000 };
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(), iv);
  cipher.setAAD(Buffer.from('hocalist-native-billing-v1'));
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(receipt), 'utf8'), cipher.final()]);
  return { ticket: Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64url'), receipt };
}
export function openNativeBillingTicket(ticket: string, now = Date.now()): NativeBillingTicket {
  if (!/^[A-Za-z0-9_-]{50,8192}$/.test(ticket)) throw new Error('invalid_ticket');
  const data = Buffer.from(ticket, 'base64url');
  const decipher = createDecipheriv('aes-256-gcm', key(), data.subarray(0, 12));
  decipher.setAAD(Buffer.from('hocalist-native-billing-v1'));
  decipher.setAuthTag(data.subarray(12, 28));
  const receipt = JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString('utf8')) as NativeBillingTicket;
  if (typeof receipt.token !== 'string' || typeof receipt.user !== 'string' ||
      !/^[a-f0-9]{64}$/.test(receipt.nonce) || !Number.isSafeInteger(receipt.expires) ||
      receipt.expires <= now || receipt.expires > now + 90_000) throw new Error('expired_ticket');
  return receipt;
}

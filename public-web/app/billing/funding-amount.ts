// Decimal text is converted without accepting exponent notation or rounding
// fractions of a credit cent. The server remains authoritative at checkout.
export function standardWalletAmount(value: string): number | null {
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(value.trim());
  if (!match) return null;
  const amount = Number(match[1]) * 100 + Number((match[2] ?? '').padEnd(2, '0'));
  return Number.isSafeInteger(amount) && amount >= 50 && amount < 2000 ? amount : null;
}

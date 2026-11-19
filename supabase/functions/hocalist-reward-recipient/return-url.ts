export function buyerPayoutReturnUrl(configured: string, origin: string | null): string {
  const previewOrigins = [
    "http://localhost:7359", "http://127.0.0.1:7359",
    "http://localhost:7368", "http://127.0.0.1:7368",
  ];
  const url = new URL(configured);
  if (origin && previewOrigins.includes(origin)) {
    return origin + "/?returnTo=buyer-rewards";
  }
  if (origin === url.origin) url.searchParams.set("returnTo", "buyer-rewards");
  return url.href;
}

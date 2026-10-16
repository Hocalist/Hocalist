// Provider-neutral payout contract for the Hocalist commercial worker.
//
// The executor only knows this interface. No real provider is named, imported
// or called here: the coordinator wires a verified adapter after account,
// country and recipient eligibility is established.

export interface PayoutRequest {
  withdrawalId: string;
  /** Stable per-attempt intent key. Abandoned attempts were never submitted. */
  requestKey: string;
  amountMinor: number;
  feeMinor: number;
  netMinor: number;
  currency: string;
}

export type PayoutResult =
  | { state: "succeeded"; reference: string }
  | { state: "pending"; reference: string }
  | { state: "failed"; reason: string };

export interface PayoutProvider {
  readonly key: string;
  submit(request: PayoutRequest): Promise<PayoutResult>;
  poll(reference: string): Promise<PayoutResult>;
}

/** The injected provider cannot be used for this configured key. */
export class PayoutConfigurationError extends Error {
  readonly reason: string;

  constructor(reason: string) {
    super(`payout_configuration_error:${reason}`);
    this.name = "PayoutConfigurationError";
    this.reason = reason;
  }
}

/** A provider transport/response failure. The attempt stays claimed. */
export class PayoutProviderError extends Error {
  readonly reason: string;

  constructor(reason: string) {
    super(`payout_provider_error:${reason}`);
    this.name = "PayoutProviderError";
    this.reason = reason;
  }
}

/** One acknowledged mutation per intent; unknown outcomes retain exact payload. */
export class AdminIntent {
  private pending: { operation: string; encoded: string; key: string } | null = null;
  constructor(private readonly allocate: () => string = () => crypto.randomUUID()) {}
  prepare(operation: string, input: Record<string, unknown>) {
    const encoded = JSON.stringify(input);
    if (this.pending && (this.pending.operation !== operation || this.pending.encoded !== encoded)) {
      throw new Error("Retry the unresolved change before starting another change.");
    }
    this.pending ??= { operation, encoded, key: this.allocate() };
    return { ...this.pending, input: JSON.parse(this.pending.encoded) as Record<string, unknown> };
  }
  acknowledged() { this.pending = null; }
}

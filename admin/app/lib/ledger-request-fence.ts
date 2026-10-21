export class LedgerRequestFence {
  private version = 0;

  begin(): number {
    return ++this.version;
  }

  accepts(version: number): boolean {
    return version === this.version;
  }

  invalidate(): void {
    ++this.version;
  }
}

import { test } from "node:test";
import assert from "node:assert/strict";
import { LedgerRequestFence } from "../app/lib/ledger-request-fence";

test("delayed seller response cannot replace a newer selection", async () => {
  const fence = new LedgerRequestFence();
  let finish!: () => void;
  const delayed = new Promise<void>((resolve) => { finish = resolve; });
  const first = fence.begin();
  let displayed = "";
  const oldRequest = delayed.then(() => {
    if (fence.accepts(first)) displayed = "seller A";
  });
  const second = fence.begin();
  if (fence.accepts(second)) displayed = "seller B";
  finish();
  await oldRequest;
  assert.equal(displayed, "seller B");
});

test("refresh or unmount rejects both stale success and failure", () => {
  const fence = new LedgerRequestFence();
  const request = fence.begin();
  fence.invalidate();
  assert.equal(fence.accepts(request), false);
  const retry = fence.begin();
  assert.equal(fence.accepts(retry), true);
});

import assert from "node:assert/strict";
import test from "node:test";
import { AdminIntent } from "../app/lib/admin-intent";

test("unknown mutation result retains the key and original payload", () => {
  let count = 0;
  const intent = new AdminIntent(() => `key-${++count}`);
  const input = { location_id: "location", expected_revision: 7, timezone_id: "America/New_York" };
  const first = intent.prepare("location.update", input);
  first.input.expected_revision = 8;
  assert.deepEqual(intent.prepare("location.update", input), {
    operation: "location.update", encoded: JSON.stringify(input), key: "key-1", input,
  });
  assert.throws(() => intent.prepare("location.update", {...input, expected_revision: 8}));
  assert.throws(() => intent.prepare("location.create", input));
  intent.acknowledged();
  assert.equal(intent.prepare("location.update", input).key, "key-2");
});

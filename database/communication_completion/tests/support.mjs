// Shared disposable-PostgreSQL helpers for the communications completion
// suites. PGlite is single-connection deterministic SQL proof, never live or
// concurrency proof.
import assert from 'node:assert/strict';
import { callAs } from '../../outcomes/tests/fixture.mjs';

export const rpc = (db, user, signature, params) =>
  callAs(db, 'authenticated', user, `SELECT hocalist.${signature} AS v`, params);

export const chat = (db, user, action, conversation, extra = []) =>
  rpc(
    db,
    user,
    `chat_${action}(${['$1', ...extra.map((_, i) => `$${i + 2}`)].join(',')})`,
    [conversation, ...extra],
  );

export async function expectDenied(promise, messagePart, code = '42501') {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${messagePart}: got ${error.code} ${error.message}`);
    if (messagePart) assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  assert.fail(`expected SQLSTATE ${code} for ${messagePart}`);
}

// PGlite 0.5.8 `close()` can wait forever after a statement failed inside this
// disposable harness. The database is in-memory and this process owns it, so
// suites call this instead of `close()`; nothing is shared with another
// process or a live project.
export async function endSuite(_db) {}

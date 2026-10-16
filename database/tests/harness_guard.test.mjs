// Guard tests for the opt-in real-PostgreSQL harnesses. No external database
// is required: these validate the pure target/content rules that protect an
// unrelated local database from destructive setup.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertConcurrencyTarget,
  assertEmptyTargetContents,
  concurrencySkipReason,
} from './harness_guard.mjs';

const validUrl = 'postgres://postgres:postgres@127.0.0.1:5432/hocalist_test';

test('real-PostgreSQL harness target guard', async (t) => {
  await t.test('missing URL reports NOT RUN instead of failing', () => {
    assert.match(concurrencySkipReason({ databaseUrl: '' }), /NOT RUN/);
    assert.equal(concurrencySkipReason({ databaseUrl: validUrl }), null);
  });

  await t.test('shared Supabase and live project targets are always refused', () => {
    for (const url of [
      'postgres://u:p@db.icqwbzswokoulatomgql.supabase.co:5432/hocalist_test',
      'postgres://u:p@aws-0-eu-central-1.pooler.supabase.com:5432/hocalist_test',
    ]) {
      assert.throws(
        () => assertConcurrencyTarget({ databaseUrl: url, acknowledged: true }),
        /refusing the shared Supabase project/,
      );
    }
  });

  await t.test('acknowledgement is required', () => {
    assert.throws(
      () => assertConcurrencyTarget({ databaseUrl: validUrl, acknowledged: false }),
      /HOCALIST_ALLOW_DISPOSABLE_DB/,
    );
  });

  await t.test('reserved databases are refused even on localhost', () => {
    for (const name of ['postgres', 'template0', 'template1']) {
      assert.throws(
        () => assertConcurrencyTarget({
          databaseUrl: `postgres://postgres:postgres@127.0.0.1:5432/${name}`,
          acknowledged: true,
        }),
        /reserved database/,
        name,
      );
    }
  });

  await t.test('non-disposable names are refused even on localhost', () => {
    assert.throws(
      () => assertConcurrencyTarget({
        databaseUrl: 'postgres://postgres:postgres@localhost:5432/hocalist',
        acknowledged: true,
      }),
      /must contain test, disposable, scratch or tmp/,
    );
  });

  await t.test('disposable names pass only with acknowledgement', () => {
    assert.deepEqual(
      assertConcurrencyTarget({ databaseUrl: validUrl, acknowledged: true }),
      { database: 'hocalist_test', host: '127.0.0.1' },
    );
    assert.equal(
      assertConcurrencyTarget({
        databaseUrl: 'postgres://u:p@db.example.internal:5432/hocalist_disposable',
        acknowledged: true,
      }).database,
      'hocalist_disposable',
    );
    assert.equal(
      assertConcurrencyTarget({
        databaseUrl: 'postgres://u:p@db.example.internal:5432/hocalist_scratch',
        acknowledged: true,
      }).database,
      'hocalist_scratch',
    );
  });

  await t.test('existing target contents are refused before any mutation', () => {
    assert.throws(() => assertEmptyTargetContents({ schemas: ['hocalist'] }), /non-empty target/);
    assert.throws(() => assertEmptyTargetContents({ schemas: ['auth'] }), /non-empty target/);
    assert.throws(() => assertEmptyTargetContents({ publicRelations: 1 }), /non-empty target/);
    assert.throws(() => assertEmptyTargetContents({ publicFunctions: 2 }), /non-empty target/);
    assert.doesNotThrow(() => assertEmptyTargetContents({}));
  });
});

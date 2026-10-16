import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createDisposableDb, applySignupSeed, applyAccountDrafts } from '../tests/fixture.mjs';
const sql = path => readFile(new URL(path, import.meta.url), 'utf8');

test('single catalogue scan preserves zones, authentication and exact grants', async () => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await applyAccountDrafts(db);
    await db.exec(await sql('../chat/010_chat_foundation.sql'));
    await db.exec(await sql('../marketplace/020_marketplace_foundation.sql'));
    await db.query("SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000000a', false)");
    const previous = (await db.query('SELECT hocalist.marketplace_timezones() AS value')).rows[0].value;
    await db.exec(await sql('./preflight.sql'));
    await db.exec(await sql('./190_timezone_catalogue.sql'));
    await db.exec(await sql('./verify.sql'));
    await db.exec('SET ROLE authenticated');
    const next = (await db.query('SELECT hocalist.marketplace_timezones() AS value')).rows[0].value;
    assert.deepEqual(next, previous);
    assert.ok(next.items.includes('America/Chicago'));
    assert.ok(!next.items.includes('UTC'));
    await db.query("SELECT set_config('request.jwt.claim.sub', '', false)");
    await assert.rejects(db.query('SELECT hocalist.marketplace_timezones()'), /authentication_required/);
    await db.exec('RESET ROLE');
    await assert.rejects(db.exec(await sql('./190_timezone_catalogue.sql')), /definition drift/);
    await db.exec('ROLLBACK');
    await db.exec('GRANT EXECUTE ON FUNCTION hocalist.marketplace_timezones() TO anon');
    await assert.rejects(db.exec(await sql('./verify.sql')), /privilege drift/);
  } finally { await db.close(); }
});

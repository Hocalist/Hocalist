// Validates the guarded communications-completion rollout against a disposable
// copy of the known deployed baseline (account/provider, chat 010, marketplace
// 020, meetings 040, outcomes 080, notifications 030/031/032, calls 110).
// PGlite is single-connection: not concurrency or live proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../../tests/fixture.mjs';
import { endSuite } from './support.mjs';

const sql = (path) => readFile(new URL(path, import.meta.url), 'utf8');

const preflightSql = await sql('../rollout/preflight.sql');
const applySql = await sql('../rollout/apply.sql');
const verifySql = await sql('../rollout/verify.sql');
const containmentSql = await sql('../rollout/containment.sql');
const guardSql = await sql('../guard.sql');
const verifyBlockSql = await sql('../verify_block.sql');

const baselineFiles = [
  '../../rollout/account_apply.sql',
  '../../provider-rollout/apply.sql',
  '../../chat/010_chat_foundation.sql',
  '../../marketplace/020_marketplace_foundation.sql',
  '../../meetings/040_meetings_foundation.sql',
  '../../outcomes/080_sale_confirmation.sql',
  '../../notifications/030_notification_inbox.sql',
  '../../notifications/031_notification_producers.sql',
  '../../notifications/032_push_queue_bridge.sql',
  '../../calls/110_call_signaling.sql',
];

async function run(db, script) {
  try {
    await db.exec(script);
    return { ok: true };
  } catch (error) {
    await db.exec('ROLLBACK').catch(() => {});
    return { ok: false, error };
  }
}

async function knownBaseline({ realtime = false } = {}) {
  const db = await createDisposableDb();
  await applySignupSeed(db);
  await applyStripeInbox(db);
  for (const path of baselineFiles) {
    const result = await run(db, await sql(path));
    assert.equal(result.ok, true, `${path}: ${result.error?.message}`);
  }
  if (realtime) await db.exec('CREATE PUBLICATION supabase_realtime;');
  return db;
}

const normalize = (text) => text.replace(/\r\n/g, '\n').trim();

test('rollout applies, verifies, aborts on repeat and contains cleanly', async () => {
  const db = await knownBaseline();
  try {
    assert.equal(normalize(applySql).includes(normalize(guardSql)), true);
    assert.equal(normalize(preflightSql).includes(normalize(guardSql)), true);
    assert.equal(normalize(applySql).includes(normalize(verifyBlockSql)), true);
    assert.equal(normalize(verifySql).includes(normalize(verifyBlockSql)), true);

    assert.equal((await run(db, preflightSql)).ok, true, 'preflight passes');
    const applyResult = await run(db, applySql);
    if (!applyResult.ok) throw applyResult.error;
    assert.equal((await run(db, verifySql)).ok, true, 'verify passes');
    const repeat = await run(db, applySql);
    assert.equal(repeat.ok, false, 'repeat apply aborts');
    assert.match(repeat.error.message, /already exists|preflight failed/);
    assert.equal((await run(db, preflightSql)).ok, false, 'second preflight aborts');

    // The generated verification rejects a permissive helper that merely
    // mentions the block table, even though the body "contains" the marker.
    await db.exec(
      `CREATE OR REPLACE FUNCTION hocalist.media_read_chat(p_user uuid, p_image uuid)
       RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
         SELECT true /* conversation_blocks */
       $$;`,
    );
    const verifyDrift = await run(db, verifySql);
    assert.equal(verifyDrift.ok, false, 'verify rejects the permissive body');
    assert.match(
      verifyDrift.error.message,
      /not the reviewed corrected definition/,
    );
    await db.exec('DROP FUNCTION hocalist.media_read_chat(uuid,uuid)');

    // History created before containment remains in place afterwards.
    assert.equal((await run(db, containmentSql)).ok, true, 'containment succeeds');
    const acl = async (signature) =>
      (
        await db.query(
          "SELECT has_function_privilege('authenticated', $1, 'EXECUTE') AS v",
          [`hocalist.${signature}`],
        )
      ).rows[0].v;
    assert.equal(await acl('chat_block(uuid,text)'), false);
    assert.equal(await acl('chat_search(text,integer,text,uuid)'), false);
    assert.equal(await acl('call_status(uuid,bigint)'), false);
    assert.equal(
      (
        await db.query(
          "SELECT has_table_privilege('authenticated','hocalist.chat_change_signals','SELECT') AS v",
        )
      ).rows[0].v,
      false,
    );
    for (const trigger of [
      'conversation_messages:chat_signal_message',
      'calls:notification_call_ringing',
      'calls:notification_call_status',
    ]) {
      const [table, name] = trigger.split(':');
      assert.equal(
        (
          await db.query(
            `SELECT count(*)::int AS n FROM pg_trigger
             WHERE tgrelid=('hocalist.' || $1)::regclass AND tgname=$2 AND NOT tgisinternal`,
            [table, name],
          )
        ).rows[0].n,
        0,
      );
    }
    // Replaced definitions and durable rows stay in place.
    assert.equal(
      (
        await db.query(
          "SELECT position('conversation_blocked' in pg_get_functiondef(to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)'))) AS v",
        )
      ).rows[0].v > 0,
      true,
    );
    assert.equal(
      (
        await db.query(
          "SELECT count(*)::int AS n FROM pg_class WHERE relname IN ('conversation_blocks','chat_change_signals')",
        )
      ).rows[0].n,
      2,
    );
    // Deployed chat still works after containment.
    assert.equal(
      (
        await db.query(
          "SELECT has_function_privilege('authenticated','hocalist.chat_send(uuid,text,text)','EXECUTE') AS v",
        )
      ).rows[0].v,
      true,
    );
  } finally {
    await endSuite(db);
  }
});

test('publication change stays least-exposure and containment removes it', async () => {
  const db = await knownBaseline({ realtime: true });
  try {
    assert.equal((await run(db, preflightSql)).ok, true, 'preflight passes with Realtime');
    const applyResult = await run(db, applySql);
    if (!applyResult.ok) throw applyResult.error;
    const published = await db.query(
      `SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname='supabase_realtime'`,
    );
    assert.deepEqual(
      published.rows.map((row) => `${row.schemaname}.${row.tablename}`),
      ['hocalist.chat_change_signals'],
    );
    assert.equal((await run(db, containmentSql)).ok, true);
    const after = await db.query(
      `SELECT count(*)::int AS n FROM pg_publication_tables WHERE pubname='supabase_realtime'`,
    );
    assert.equal(after.rows[0].n, 0);
  } finally {
    await endSuite(db);
  }
});

test('prerequisite drift aborts before any change', async () => {
  const db = await knownBaseline();
  try {
    await db.exec(
      "CREATE OR REPLACE FUNCTION hocalist.call_command(p_action text, p_input jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;",
    );
    const result = await run(db, preflightSql);
    assert.equal(result.ok, false);
    assert.match(result.error.message, /prerequisite drift: hocalist.call_command/);
    assert.equal(
      (
        await db.query(
          "SELECT count(*)::int AS n FROM pg_class WHERE relnamespace='hocalist'::regnamespace AND relname IN ('conversation_blocks','chat_change_signals')",
        )
      ).rows[0].n,
      0,
      'drift aborts before creating objects',
    );
  } finally {
    await endSuite(db);
  }
});


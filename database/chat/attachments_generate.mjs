// Generate the guarded chat 011 chat-attachments rollout bundle.
//
// Runs against disposable PGlite only; never opens a live connection. The
// bundle is additive on top of the deployed chat 010 and media 100 foundation.
// Media 101 may be applied before or after it: both gateway replacements carry
// the same conditional dispatch, so the exact prerequisite hash is unchanged.
import { readFile } from 'node:fs/promises';
import {
  applyAccountDrafts,
  applySignupSeed,
  applyStripeInbox,
  createDisposableDb,
} from '../tests/fixture.mjs';
import {
  absenceGuard,
  driftGuard,
  functionHashes,
  functionVerify,
  migrationBody,
  presenceGuard,
  writeBundle,
} from '../tests/rollout_bundle.mjs';

const base = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, base), 'utf8');

const BASELINE = [
  '../provider-rollout/apply.sql',
  './010_chat_foundation.sql',
  '../marketplace/020_marketplace_foundation.sql',
  '../meetings/040_meetings_foundation.sql',
  '../media/100_private_images.sql',
];

const PREREQUISITE_FUNCTIONS = [
  'hocalist.chat_send(uuid,text,text)',
  'hocalist.chat_assert_participant(uuid,uuid)',
  'hocalist.media_gateway(uuid,text,jsonb)',
];
const PREREQUISITE_RELATIONS = [
  { test: "to_regclass('hocalist.conversations') IS NOT NULL", label: 'hocalist.conversations' },
  { test: "to_regclass('hocalist.conversation_members') IS NOT NULL", label: 'hocalist.conversation_members' },
  { test: "to_regclass('hocalist.conversation_messages') IS NOT NULL", label: 'hocalist.conversation_messages' },
  { test: "to_regclass('hocalist.media_images') IS NOT NULL", label: 'hocalist.media_images' },
];
const ABSENT_OBJECTS = [
  {
    test: "(SELECT count(*) FROM pg_attribute WHERE attrelid='hocalist.conversation_messages'::regclass AND attname='attachment_media_ids' AND NOT attisdropped) > 0",
    label: 'hocalist.conversation_messages.attachment_media_ids',
  },
  { test: "to_regprocedure('hocalist.chat_send_attachment(uuid,text,text,jsonb)') IS NOT NULL", label: 'hocalist.chat_send_attachment(uuid,text,text,jsonb)' },
  { test: "to_regprocedure('hocalist.chat_validate_attachments()') IS NOT NULL", label: 'hocalist.chat_validate_attachments()' },
  { test: "to_regprocedure('hocalist.media_read_chat(uuid,uuid)') IS NOT NULL", label: 'hocalist.media_read_chat(uuid,uuid)' },
  { test: "EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.conversation_messages'::regclass AND tgname='chat_message_validate_attachments' AND NOT tgisinternal)", label: 'hocalist.chat_message_validate_attachments' },
];
const INSTALLED_FUNCTIONS = [
  'hocalist.chat_validate_attachments()',
  'hocalist.chat_send_attachment(uuid,text,text,jsonb)',
  'hocalist.media_read_chat(uuid,uuid)',
  'hocalist.media_gateway(uuid,text,jsonb)',
];
const GRANTS = {
  'hocalist.chat_validate_attachments()': [],
  'hocalist.chat_send_attachment(uuid,text,text,jsonb)': ['authenticated'],
  'hocalist.media_read_chat(uuid,uuid)': [],
  'hocalist.media_gateway(uuid,text,jsonb)': ['service_role'],
};

const db = await createDisposableDb();
try {
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of BASELINE) await db.exec(await read(path));

  const before = await functionHashes(db, PREREQUISITE_FUNCTIONS);
  const body = migrationBody(await read('./011_chat_attachments.sql'), '011_chat_attachments.sql');
  await db.exec(await read('./011_chat_attachments.sql'));
  const after = await functionHashes(db, INSTALLED_FUNCTIONS);

  // Media 101 may be applied first; its gateway body is this bundle's own
  // post-apply body, so both reviewed bodies are accepted as prerequisites.
  const prerequisites = new Map(before);
  prerequisites.set('hocalist.media_gateway(uuid,text,jsonb)', [
    before.get('hocalist.media_gateway(uuid,text,jsonb)'),
    after.get('hocalist.media_gateway(uuid,text,jsonb)'),
  ]);

  const preflight = [
    '-- Chat 010 and media 100 prerequisites; target objects must be absent.',
    presenceGuard(PREREQUISITE_RELATIONS),
    driftGuard(prerequisites),
    absenceGuard(ABSENT_OBJECTS),
  ].join('\n');
  const verify = [
    "IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='hocalist.conversation_messages'::regclass AND attname='attachment_media_ids' AND attnotnull AND NOT attisdropped) THEN RAISE EXCEPTION 'Missing attachment_media_ids column'; END IF;",
    "IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='hocalist.conversation_messages'::regclass AND conname='chat_attachment_shape') THEN RAISE EXCEPTION 'Missing attachment shape constraint'; END IF;",
    "IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='hocalist.conversation_messages'::regclass AND conname='conversation_messages_kind_check' AND pg_get_constraintdef(oid) LIKE '%attachment%') THEN RAISE EXCEPTION 'Message kind constraint is missing attachment'; END IF;",
    "IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.conversation_messages'::regclass AND tgname='chat_message_validate_attachments' AND NOT tgisinternal AND tgenabled='O') THEN RAISE EXCEPTION 'Missing attachment validation trigger'; END IF;",
    functionVerify(after, GRANTS),
  ].join('\n');
  const containment = [
    '-- Revokes the client capabilities this bundle added; the attachment column,',
    '-- constraints and trigger stay in place, so this is not a destructive rollback.',
    'BEGIN;',
    'REVOKE ALL ON FUNCTION hocalist.chat_send_attachment(uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;',
    'REVOKE ALL ON FUNCTION hocalist.chat_validate_attachments() FROM PUBLIC,anon,authenticated,service_role;',
    'REVOKE ALL ON FUNCTION hocalist.media_read_chat(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;',
    'GRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;',
    'COMMIT;',
  ].join('\n');

  await writeBundle(base, {
    generator: 'database/chat/attachments_generate.mjs',
    title: 'Guarded chat 011 chat-attachments rollout.',
    preflight,
    body,
    verify,
    containment,
    directory: 'attachments-rollout/',
  });
  console.log(`Generated chat 011 bundle: ${after.size} verified functions; no live connection.`);
} finally {
  await db.close();
}

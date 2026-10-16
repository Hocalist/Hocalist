// Generate the guarded media 101 profile-avatar rollout bundle.
//
// Runs against disposable PGlite only; never opens a live connection. The
// bundle is additive on top of the deployed account 003/004, chat 010 and
// media 100 foundation, which is the state the coordinator applies in order.
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
  '../chat/010_chat_foundation.sql',
  '../marketplace/020_marketplace_foundation.sql',
  '../meetings/040_meetings_foundation.sql',
  './100_private_images.sql',
];

const PREREQUISITE_FUNCTIONS = ['hocalist.media_gateway(uuid,text,jsonb)'];
const PREREQUISITE_RELATIONS = [
  { test: "to_regclass('hocalist.role_profiles') IS NOT NULL", label: 'hocalist.role_profiles' },
  { test: "to_regclass('hocalist.memberships') IS NOT NULL", label: 'hocalist.memberships' },
  { test: "to_regclass('hocalist.media_images') IS NOT NULL", label: 'hocalist.media_images' },
  { test: "to_regclass('hocalist.command_receipts') IS NOT NULL", label: 'hocalist.command_receipts' },
];
const ABSENT_OBJECTS = [
  {
    test: "(SELECT count(*) FROM pg_attribute WHERE attrelid='hocalist.role_profiles'::regclass AND attname='image_media_id' AND NOT attisdropped) > 0",
    label: 'hocalist.role_profiles.image_media_id',
  },
  { test: "to_regprocedure('hocalist.profile_avatar_validate()') IS NOT NULL", label: 'hocalist.profile_avatar_validate()' },
  { test: "to_regprocedure('hocalist.profile_avatar_update(text,text,bigint,uuid)') IS NOT NULL", label: 'hocalist.profile_avatar_update(text,text,bigint,uuid)' },
  { test: "to_regprocedure('hocalist.member_avatar(uuid)') IS NOT NULL", label: 'hocalist.member_avatar(uuid)' },
  { test: "to_regprocedure('hocalist.media_read_profile(uuid,uuid)') IS NOT NULL", label: 'hocalist.media_read_profile(uuid,uuid)' },
];
const INSTALLED_FUNCTIONS = [
  'hocalist.profile_avatar_validate()',
  'hocalist.profile_avatar_update(text,text,bigint,uuid)',
  'hocalist.member_avatar(uuid)',
  'hocalist.media_read_profile(uuid,uuid)',
  'hocalist.media_gateway(uuid,text,jsonb)',
];
const GRANTS = {
  'hocalist.profile_avatar_validate()': [],
  'hocalist.profile_avatar_update(text,text,bigint,uuid)': ['authenticated'],
  'hocalist.member_avatar(uuid)': ['authenticated'],
  'hocalist.media_read_profile(uuid,uuid)': [],
  'hocalist.media_gateway(uuid,text,jsonb)': ['service_role'],
};

const db = await createDisposableDb();
try {
  await applySignupSeed(db);
  await applyStripeInbox(db);
  await applyAccountDrafts(db);
  for (const path of BASELINE) await db.exec(await read(path));

  const before = await functionHashes(db, PREREQUISITE_FUNCTIONS);
  const body = migrationBody(await read('./101_profile_avatar.sql'), '101_profile_avatar.sql');
  await db.exec(await read('./101_profile_avatar.sql'));
  const after = await functionHashes(db, INSTALLED_FUNCTIONS);

  // Chat 011 may be applied first; its gateway body is this bundle's own
  // post-apply body, so both reviewed bodies are accepted as prerequisites.
  const prerequisites = new Map(before);
  prerequisites.set('hocalist.media_gateway(uuid,text,jsonb)', [
    before.get('hocalist.media_gateway(uuid,text,jsonb)'),
    after.get('hocalist.media_gateway(uuid,text,jsonb)'),
  ]);

  const preflight = [
    '-- Account 003/004 and media 100 prerequisites; target objects must be absent.',
    presenceGuard(PREREQUISITE_RELATIONS),
    driftGuard(prerequisites),
    absenceGuard(ABSENT_OBJECTS),
  ].join('\n');
  const verify = [
    "IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='hocalist.role_profiles'::regclass AND attname='image_media_id' AND NOT attisdropped) THEN RAISE EXCEPTION 'Missing profile image reference column'; END IF;",
    "IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.role_profiles'::regclass AND tgname='profile_avatar_validate_reference' AND NOT tgisinternal AND tgenabled='O') THEN RAISE EXCEPTION 'Missing profile avatar validation trigger'; END IF;",
    functionVerify(after, GRANTS),
  ].join('\n');
  const containment = [
    '-- Revokes the client capabilities this bundle added; the reference column',
    '-- and validation trigger stay in place, so this is not a destructive rollback.',
    'BEGIN;',
    'REVOKE ALL ON FUNCTION hocalist.profile_avatar_update(text,text,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;',
    'REVOKE ALL ON FUNCTION hocalist.member_avatar(uuid) FROM PUBLIC,anon,authenticated,service_role;',
    'REVOKE ALL ON FUNCTION hocalist.media_read_profile(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;',
    'GRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;',
    'COMMIT;',
  ].join('\n');

  await writeBundle(base, {
    generator: 'database/media/generate.mjs',
    title: 'Guarded media 101 profile-avatar rollout.',
    preflight,
    body,
    verify,
    containment,
  });
  console.log(`Generated media 101 bundle: ${after.size} verified functions; no live connection.`);
} finally {
  await db.close();
}

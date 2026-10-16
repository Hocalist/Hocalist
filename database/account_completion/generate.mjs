// Generate the reviewable account-completion rollout bundle (130-133).
//
// Uses disposable PGlite only; never opens a live connection. The bundle is
// additive against the current checkpoint plus the pending September 26
// upgrade bundle and media 100/101, which is the state the coordinator applies
// in order.
import { writeFile, mkdir } from 'node:fs/promises';
import { createAccountCompletionDb } from './tests/fixture.mjs';

const base = new URL('./', import.meta.url);
const quote = (x) => "'" + x.replaceAll("'", "''") + "'";

const MIGRATIONS = [
  '130_account_lifecycle.sql',
  '131_profile_categories.sql',
  '132_review_evidence.sql',
  '133_media_cleanup.sql',
];

const newTables = [
  'account_consent_documents',
  'account_consents',
  'account_export_requests',
  'account_exports',
  'account_deletion_requests',
  'role_profile_categories',
  'review_evidence_links',
  'evidence_audit',
  'evidence_holds',
  'media_cleanup_audit',
];

const replaced = ['hocalist.media_gateway(uuid,text,jsonb)'];

const clientGrants = {
  'hocalist.account_lifecycle_status()': ['authenticated'],
  'hocalist.account_consent_record(text,jsonb)': ['authenticated'],
  'hocalist.account_export_request(text)': ['authenticated'],
  'hocalist.account_export_read(uuid)': ['authenticated'],
  'hocalist.account_deletion_request(text)': ['authenticated'],
  'hocalist.account_deletion_cancel(text,jsonb)': ['authenticated'],
  'hocalist.admin_account_lifecycle_command(text,text,jsonb)': ['authenticated'],
  'hocalist.seller_profile_categories()': ['authenticated'],
  'hocalist.member_seller_categories(uuid)': ['authenticated'],
  'hocalist.profile_categories_update(text,bigint,jsonb)': ['authenticated'],
  'hocalist.review_evidence_attach(text,jsonb)': ['authenticated'],
  'hocalist.review_evidence_detach(text,jsonb)': ['authenticated'],
  'hocalist.report_evidence_attach(text,jsonb)': ['authenticated'],
  'hocalist.report_evidence_detach(text,jsonb)': ['authenticated'],
  'hocalist.admin_review_evidence(integer)': ['authenticated'],
  'hocalist.admin_evidence_hold(text,jsonb)': ['authenticated'],
};

const serverOnly = [
  'hocalist.account_lifecycle_holds(uuid)',
  'hocalist.account_export_build(uuid)',
  'hocalist.review_evidence_validate()',
  'hocalist.media_read_review_evidence(uuid,uuid)',
  'hocalist.media_referenced(uuid)',
  'hocalist.media_cleanup_hash(integer,jsonb,jsonb)',
];

const serviceOnly = [
  'hocalist.media_cleanup_plan(integer)',
  'hocalist.media_cleanup_apply(text,jsonb)',
  'hocalist.media_gateway(uuid,text,jsonb)',
];

const fnHashQuery =
  "SELECT p.oid::regprocedure::text AS signature, md5(replace(pg_get_functiondef(p.oid),chr(13),'')) AS hash " +
  "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='hocalist'";
const hashOf = async (db, signatures) => {
  const rows = (await db.query(fnHashQuery)).rows;
  const map = new Map(rows.map((row) => [row.signature, row.hash]));
  return signatures.map((signature) => {
    const hash = map.get(signature);
    if (!hash) throw new Error(`missing prerequisite function ${signature}`);
    return { signature, hash };
  });
};

const db = await createAccountCompletionDb({ migrations: [] });
try {
  const before = await hashOf(db, replaced);
  const tablesBefore = new Set(
    (await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows.map((r) => r.tablename),
  );
  for (const table of newTables) {
    if (tablesBefore.has(table)) throw new Error(`target table already exists: ${table}`);
  }

  const chunks = [];
  for (const file of MIGRATIONS) {
    const sql = await load(new URL(file, base));
    await db.exec(sql);
    chunks.push(sql.replace(/^BEGIN;\s*$/m, '').replace(/^COMMIT;\s*$/m, ''));
  }

  const after = await hashOf(
    db,
    Object.keys(clientGrants).concat(serverOnly).concat(serviceOnly),
  );
  const tablesAfter = new Set(
    (await db.query("SELECT tablename FROM pg_tables WHERE schemaname='hocalist'")).rows.map((r) => r.tablename),
  );
  for (const table of newTables) {
    if (!tablesAfter.has(table)) throw new Error(`migration did not create ${table}`);
  }

  const preflight =
    'DO $guard$ BEGIN\n' +
    before
      .map(
        (f) =>
          `IF to_regprocedure(${quote(f.signature)}) IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure(${quote(f.signature)})),chr(13),''))<>${quote(f.hash)} THEN RAISE EXCEPTION 'Prerequisite drift: ${f.signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newTables
      .map(
        (t) =>
          `IF to_regclass('hocalist.${t}') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ${t}'; END IF;`,
      )
      .join('\n') +
    '\nEND $guard$;\n';

  const verify =
    'DO $verify$ DECLARE f oid; r text; priv text; BEGIN\n' +
    after
      .map(
        (f) =>
          `f:=to_regprocedure(${quote(f.signature)});\nIF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>${quote(f.hash)} THEN RAISE EXCEPTION 'Function drift: ${f.signature}'; END IF;`,
      )
      .join('\n') +
    '\n' +
    newTables
      .map(
        (t) =>
          `IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.${t}')),false) THEN RAISE EXCEPTION 'Missing RLS: ${t}'; END IF;\nFOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP IF has_table_privilege(r,'hocalist.${t}',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: ${t} % %',r,priv; END IF; END LOOP; END LOOP;`,
      )
      .join('\n') +
    '\n' +
    Object.entries(clientGrants)
      .map(
        ([signature, roles]) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[${roles.map(quote).join(',')}]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: ${signature} %',r; END IF; END LOOP;`,
      )
      .join('\n') +
    '\n' +
    serverOnly
      .map(
        (signature) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Server-only helper exposed: ${signature}'; END IF; END LOOP;`,
      )
      .join('\n') +
    '\n' +
    serviceOnly
      .map(
        (signature) =>
          `FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP IF has_function_privilege(r,to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Client grant on service helper: ${signature}'; END IF; END LOOP;\nIF NOT has_function_privilege('service_role',to_regprocedure(${quote(signature)}),'EXECUTE') THEN RAISE EXCEPTION 'Missing service grant: ${signature}'; END IF;`,
      )
      .join('\n') +
    "\nIF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='hocalist.media_images'::regclass AND conname='media_images_purpose_check' AND pg_get_constraintdef(oid) LIKE '%review%' AND pg_get_constraintdef(oid) LIKE '%report%') THEN RAISE EXCEPTION 'media purpose constraint missing review/report'; END IF;\n" +
    '\nEND $verify$;\n';

  await mkdir(new URL('rollout/', base), { recursive: true });
  await writeFile(new URL('rollout/preflight.sql', base), 'BEGIN READ ONLY;\n' + preflight + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/apply.sql', base),
    "BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='120s';\n" +
      preflight +
      chunks.join('\n') +
      '\n' +
      verify +
      'COMMIT;\n',
  );
  await writeFile(new URL('rollout/verify.sql', base), 'BEGIN READ ONLY;\n' + verify + 'ROLLBACK;\n');
  await writeFile(
    new URL('rollout/containment.sql', base),
    '-- Containment for a suspicious apply: remove every client capability the\n' +
      '-- account-completion bundle added without deleting consent, export, request,\n' +
      '-- category or evidence history. Replaced function bodies stay in place; this\n' +
      '-- is not a destructive rollback.\n' +
      'BEGIN;\n' +
      Object.keys(clientGrants)
        .map((signature) => `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated,service_role;`)
        .join('\n') +
      '\n' +
      serviceOnly
        .filter((signature) => signature !== 'hocalist.media_gateway(uuid,text,jsonb)')
        .map((signature) => `REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated,service_role;`)
        .join('\n') +
      '\nGRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;\n' +
      '\nCOMMIT;\n',
  );
  console.log(
    `Generated account-completion bundle: ${chunks.length} migrations, ${newTables.length} new tables, ` +
      `${after.length} verified functions; no live connection.`,
  );
} finally {
  await db.close();
}

async function load(url) {
  const { readFile } = await import('node:fs/promises');
  return readFile(url, 'utf8');
}

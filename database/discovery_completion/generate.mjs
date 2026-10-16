// Generates the discovery_completion rollout artifacts from the reviewed
// additive migrations:
//   rollout/apply_guard.sql   - prerequisite definition/ACL guards
//   rollout/apply.sql         - guard + migrations + post-apply verification
//   rollout/verify.sql        - read-only post-apply verification
//   rollout/preflight.sql     - read-only prerequisite/inventory verification
//
// Prerequisite and package function bodies are pinned by CR-normalized
// `pg_proc.prosrc` md5, so a same-signature body replacement (for example the
// authorization helper) is detected by both apply and verify.
//
// Disposable PGlite only; never a live database.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const here = new URL('.', import.meta.url);
const read = (p) => readFile(new URL(p, here), 'utf8');

const migrations = [
  '140_discovery_leads.sql',
  '141_recommended_leads.sql',
  '142_reviews.sql',
  '143_trends_consent.sql',
  '144_discovery_enquiry.sql',
  '145_seller_outcomes.sql',
  '146_topic_sellers.sql',
];

/// Extracts the dollar-quoted body of one function exactly as PostgreSQL
/// stores it in `prosrc`, CR-normalized like the SQL guards do.
function extractBody(sql, name) {
  const start = sql.indexOf(`CREATE FUNCTION hocalist.${name}(`);
  if (start < 0) throw new Error(`missing function ${name}`);
  const asIdx = sql.indexOf('AS $$', start);
  if (asIdx < 0) throw new Error(`missing AS $$ for ${name}`);
  const bodyStart = asIdx + 'AS $$'.length;
  const bodyEnd = sql.indexOf('$$', bodyStart);
  if (bodyEnd < 0) throw new Error(`unterminated body for ${name}`);
  return sql.slice(bodyStart, bodyEnd).replace(/\r/g, '');
}

function md5(text) {
  return createHash('md5').update(text, 'utf8').digest('hex');
}

// Reviewed prerequisite definitions this package depends on.
const prerequisiteSpecs = [
  ['marketplace_assert_role(uuid,text)', '../marketplace/020_marketplace_foundation.sql', 'marketplace_assert_role'],
  ['marketplace_assert_admin(uuid)', '../marketplace/020_marketplace_foundation.sql', 'marketplace_assert_admin'],
  ['marketplace_is_admin(uuid)', '../marketplace/020_marketplace_foundation.sql', 'marketplace_is_admin'],
  ['chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)', '../chat/010_chat_foundation.sql', 'chat_open_internal'],
];

// Every function this package creates, pinned for post-apply verification.
const packageSpecs = [
  ['discovery_distance_miles(double precision,double precision,double precision,double precision)', '140_discovery_leads.sql', 'discovery_distance_miles'],
  ['discovery_declared_category_ids(uuid)', '140_discovery_leads.sql', 'discovery_declared_category_ids'],
  ['discovery_assert_active_member(uuid)', '140_discovery_leads.sql', 'discovery_assert_active_member'],
  ['discovery_origin_json()', '140_discovery_leads.sql', 'discovery_origin_json'],
  ['discovery_origin_set(text,jsonb)', '140_discovery_leads.sql', 'discovery_origin_set'],
  ['discovery_lead_json(uuid,double precision,integer,jsonb)', '140_discovery_leads.sql', 'discovery_lead_json'],
  ['marketplace_discovery_leads(text,uuid,text,integer,text,text,integer,text,bigint,bigint)', '140_discovery_leads.sql', 'marketplace_discovery_leads'],
  ['marketplace_recommended_leads(integer)', '141_recommended_leads.sql', 'marketplace_recommended_leads'],
  ['review_reviewer_label(uuid)', '142_reviews.sql', 'review_reviewer_label'],
  ['review_json(uuid)', '142_reviews.sql', 'review_json'],
  ['review_status(uuid)', '142_reviews.sql', 'review_status'],
  ['review_submit(text,jsonb)', '142_reviews.sql', 'review_submit'],
  ['review_update(text,jsonb)', '142_reviews.sql', 'review_update'],
  ['review_moderate(text,jsonb)', '142_reviews.sql', 'review_moderate'],
  ['seller_public_reputation(uuid)', '142_reviews.sql', 'seller_public_reputation'],
  ['buyer_public_profile_consent_json()', '143_trends_consent.sql', 'buyer_public_profile_consent_json'],
  ['buyer_public_profile_consent_set(text,jsonb)', '143_trends_consent.sql', 'buyer_public_profile_consent_set'],
  ['buyer_public_profile(uuid)', '143_trends_consent.sql', 'buyer_public_profile'],
  ['hocatrends_trends(integer)', '143_trends_consent.sql', 'hocatrends_trends'],
  ['hocatrends_winners(integer)', '143_trends_consent.sql', 'hocatrends_winners'],
  ['discovery_open_enquiry(text,jsonb)', '144_discovery_enquiry.sql', 'discovery_open_enquiry'],
  ['marketplace_seller_outcomes(integer)', '145_seller_outcomes.sql', 'marketplace_seller_outcomes'],
  ['hocatrends_topic_sellers(uuid,integer)', '146_topic_sellers.sql', 'hocatrends_topic_sellers'],
];

const fileCache = new Map();
async function fileText(path) {
  if (!fileCache.has(path)) fileCache.set(path, await read(path));
  return fileCache.get(path);
}

async function pinned(specs) {
  const entries = [];
  for (const [signature, file, name] of specs) {
    const body = extractBody(await fileText(file), name);
    entries.push(`'${signature}=${md5(body)}'`);
  }
  return entries;
}

function sqlArray(entries, indent) {
  const pad = ' '.repeat(indent);
  return entries.map((entry) => `${pad}${entry}`).join(',\n');
}

const prerequisiteEntries = await pinned(prerequisiteSpecs);
const packageEntries = await pinned(packageSpecs);

const guardSql = `-- GENERATED by database/discovery_completion/generate.mjs - do not edit by hand.
-- Apply-time prerequisite guard: exact definition hashes, signature inventory,
-- required columns, RLS and receipt privacy. The apply transaction includes
-- this block itself so a separately executed preflight is not relied upon.
DO $hocalist_discovery_completion_guard$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_pair text;
  v_signature text;
  v_hash text;
  v_column text;
  v_expected_functions constant text[] := ARRAY[
${sqlArray(prerequisiteEntries, 4)}
  ];
  v_required_columns constant text[] := ARRAY[
    'requests:id','requests:buyer_user_id','requests:buyer_profile_id','requests:kind',
    'requests:title','requests:description','requests:budget_min_minor','requests:budget_max_minor',
    'requests:currency_code','requests:category_id','requests:status','requests:revision',
    'requests:created_at','requests:latitude','requests:longitude','requests:acceptance_expires_at',
    'sale_confirmations:request_id','sale_confirmations:meeting_id','sale_confirmations:offer_id',
    'sale_confirmations:buyer_user_id','sale_confirmations:seller_user_id','sale_confirmations:confirmed_at',
    'marketplace_receipts:user_id','marketplace_receipts:operation','marketplace_receipts:idempotency_key',
    'marketplace_receipts:request_hash','marketplace_receipts:result',
    'memberships:id','memberships:user_id','memberships:role','memberships:status',
    'role_profiles:membership_id','role_profiles:display_name','role_profiles:area_label',
    'store_listings:id','store_listings:seller_user_id','store_listings:seller_profile_id',
    'store_listings:category_id','store_listings:status','store_listings:moderation_status',
    'catalogue_categories:id','catalogue_categories:label','catalogue_categories:status'
  ];
  v_prerequisite_tables constant text[] := ARRAY[
    'requests','sale_confirmations','marketplace_receipts','memberships',
    'role_profiles','store_listings','catalogue_categories'];
BEGIN
  FOREACH v_pair IN ARRAY v_expected_functions LOOP
    v_signature := split_part(v_pair, '=', 1);
    v_hash := split_part(v_pair, '=', 2);
    IF to_regprocedure('hocalist.' || v_signature) IS NULL THEN
      v_issues := array_append(v_issues, 'prerequisite function missing: ' || v_signature);
    ELSIF (SELECT md5(replace(prosrc, chr(13), '')) FROM pg_proc
           WHERE oid = ('hocalist.' || v_signature)::regprocedure) IS DISTINCT FROM v_hash THEN
      v_issues := array_append(v_issues, 'prerequisite definition drift: ' || v_signature);
    END IF;
  END LOOP;
  -- Exact signature inventory: no unexpected overload of an authorization
  -- boundary may shadow the reviewed one.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hocalist'
        AND p.proname IN ('marketplace_assert_role','marketplace_is_admin',
                          'marketplace_assert_admin','chat_open_internal')) <> 4 THEN
    v_issues := array_append(v_issues, 'authorization function overload inventory changed');
  END IF;
  FOREACH v_column IN ARRAY v_required_columns LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'hocalist'
        AND table_name = split_part(v_column, ':', 1)
        AND column_name = split_part(v_column, ':', 2)) THEN
      v_issues := array_append(v_issues, 'required column missing: ' || v_column);
    END IF;
  END LOOP;
  FOREACH v_column IN ARRAY v_prerequisite_tables LOOP
    IF to_regclass('hocalist.' || v_column) IS NULL THEN
      v_issues := array_append(v_issues, 'prerequisite table missing: ' || v_column);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class
               WHERE oid = ('hocalist.' || v_column)::regclass) THEN
      v_issues := array_append(v_issues, 'prerequisite RLS disabled: ' || v_column);
    END IF;
  END LOOP;
  -- Receipts and other private records stay client-inaccessible.
  IF has_table_privilege('authenticated','hocalist.marketplace_receipts','SELECT')
     OR has_table_privilege('authenticated','hocalist.marketplace_receipts','INSERT')
     OR has_table_privilege('authenticated','hocalist.marketplace_receipts','UPDATE')
     OR has_table_privilege('authenticated','hocalist.marketplace_receipts','DELETE')
     OR has_table_privilege('anon','hocalist.marketplace_receipts','SELECT') THEN
    v_issues := array_append(v_issues, 'marketplace_receipts client grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist discovery_completion prerequisite guard failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_discovery_completion_guard$;
`;

const verifyHashesSql = await read('rollout/verify_hashes.template.sql');
const verifyHashes = verifyHashesSql
  .replace('__PREREQUISITE_HASHES__', sqlArray(prerequisiteEntries, 2))
  .replace('__PACKAGE_HASHES__', sqlArray(packageEntries, 2));

const verifyBody = await read('rollout/verify_body.sql');

const header = `-- GENERATED by database/discovery_completion/generate.mjs - do not edit by hand.
-- Reviewed additive package for seller discovery, recommendations, reviews,
-- Hocatrends/Winners projections, buyer public-profile consent and the
-- origin-isolated Store/Hocatrends enquiry opener.
--
-- Each migration is its own atomic transaction with its own prerequisite
-- guard; this file also runs the shared prerequisite guard before the first
-- migration and the post-apply verification afterwards. No provider or client
-- call is made here.
`;

await writeFile(new URL('rollout/apply_guard.sql', here), guardSql, 'utf8');
console.log('wrote rollout/apply_guard.sql', guardSql.length, 'bytes');

let applySql = header;
applySql += `\n\n${guardSql}`;
for (const file of migrations) {
  applySql += `\n\n-- ===========================================================================\n`;
  applySql += `-- ${file}\n`;
  applySql += `-- ===========================================================================\n`;
  applySql += await fileText(file);
}
applySql += `\n\n-- ===========================================================================\n`;
applySql += `-- Post-apply verification (same blocks as rollout/verify.sql)\n`;
applySql += `-- ===========================================================================\n`;
applySql += verifyBody;
applySql += `\n`;
applySql += verifyHashes;
await writeFile(new URL('rollout/apply.sql', here), applySql, 'utf8');
console.log('wrote rollout/apply.sql', applySql.length, 'bytes');

const verifySql =
  `-- GENERATED by database/discovery_completion/generate.mjs - do not edit by hand.\n` +
  `-- Hocalist discovery_completion rollout verification. READ-ONLY: safe any time\n` +
  `-- after apply.sql. The verification blocks are textually identical to the\n` +
  `-- post-apply blocks in apply.sql.\n` +
  `BEGIN READ ONLY;\nSET LOCAL statement_timeout = '15s';\n` +
  verifyBody +
  `\n` +
  verifyHashes +
  `ROLLBACK;\n` +
  `SELECT 'PASS: discovery_completion objects, RLS and grants verified' AS discovery_completion_verify;\n`;
await writeFile(new URL('rollout/verify.sql', here), verifySql, 'utf8');
console.log('wrote rollout/verify.sql', verifySql.length, 'bytes');

const preflightSql =
  `-- GENERATED by database/discovery_completion/generate.mjs - do not edit by hand.\n` +
  `-- Hocalist discovery_completion preflight. READ-ONLY.\n` +
  `--\n` +
  `-- Refuses a missing/drifted prerequisite (definition hashes, authorization\n` +
  `-- inventory, required columns, RLS, receipt privacy) or a partially installed\n` +
  `-- package. The same guard is embedded in apply.sql, which does not rely on a\n` +
  `-- separately executed preflight.\n` +
  `BEGIN READ ONLY;\nSET LOCAL statement_timeout = '15s';\n` +
  guardSql +
  `\nDO $hocalist_discovery_completion_preflight$\n` +
  `DECLARE\n` +
  `  v_issues text[] := ARRAY[]::text[];\n` +
  `  v_installed integer := 0;\n` +
  `  v_fn text;\n` +
  `  v_internal constant text[] := ARRAY[\n` +
  `    'discovery_distance_miles(double precision,double precision,double precision,double precision)',\n` +
  `    'discovery_declared_category_ids(uuid)','discovery_assert_active_member(uuid)',\n` +
  `    'discovery_lead_json(uuid,double precision,integer,jsonb)',\n` +
  `    'review_reviewer_label(uuid)','review_json(uuid)'];\n` +
  `  v_deployed constant text[] := ARRAY[\n` +
  `    'chat_send(uuid,text,text)','marketplace_command(text,text,jsonb)',\n` +
  `    'sale_pin(uuid,text,text)'];\n` +
  `BEGIN\n` +
  `  IF to_regclass('hocalist.seller_discovery_origins') IS NOT NULL THEN v_installed := v_installed + 1; END IF;\n` +
  `  IF to_regprocedure('hocalist.marketplace_recommended_leads(integer)') IS NOT NULL THEN v_installed := v_installed + 1; END IF;\n` +
  `  IF to_regclass('hocalist.outcome_reviews') IS NOT NULL THEN v_installed := v_installed + 1; END IF;\n` +
  `  IF to_regclass('hocalist.buyer_public_profile_consent') IS NOT NULL THEN v_installed := v_installed + 1; END IF;\n` +
  `  IF to_regprocedure('hocalist.discovery_open_enquiry(text,jsonb)') IS NOT NULL THEN v_installed := v_installed + 1; END IF;\n` +
  `  IF to_regprocedure('hocalist.marketplace_seller_outcomes(integer)') IS NOT NULL THEN v_installed := v_installed + 1; END IF;\n` +
  `  IF to_regprocedure('hocalist.hocatrends_topic_sellers(uuid,integer)') IS NOT NULL THEN v_installed := v_installed + 1; END IF;\n` +
  `  IF v_installed NOT IN (0, 7) THEN\n` +
  `    v_issues := array_append(v_issues, 'partial installation detected (' || v_installed || '/7 objects)');\n` +
  `  END IF;\n` +
  `  IF v_installed = 7 THEN\n` +
  `    FOREACH v_fn IN ARRAY v_internal LOOP\n` +
  `      IF has_function_privilege('authenticated','hocalist.' || v_fn,'EXECUTE')\n` +
  `         OR has_function_privilege('anon','hocalist.' || v_fn,'EXECUTE') THEN\n` +
  `        v_issues := array_append(v_issues, 'internal helper is client-executable: ' || v_fn);\n` +
  `      END IF;\n` +
  `    END LOOP;\n` +
  `  END IF;\n` +
  `  FOREACH v_fn IN ARRAY v_deployed LOOP\n` +
  `    IF NOT has_function_privilege('authenticated','hocalist.' || v_fn,'EXECUTE') THEN\n` +
  `      v_issues := array_append(v_issues, 'deployed client capability missing: ' || v_fn);\n` +
  `    END IF;\n` +
  `  END LOOP;\n` +
  `  IF coalesce(array_length(v_issues,1),0) > 0 THEN\n` +
  `    RAISE EXCEPTION 'hocalist discovery_completion preflight failed: %', array_to_string(v_issues, ' | ');\n` +
  `  END IF;\n` +
  `END\n$hocalist_discovery_completion_preflight$;\n` +
  `ROLLBACK;\n` +
  `SELECT 'PASS: discovery_completion prerequisites intact; package absent or complete' AS discovery_completion_preflight;\n`;
await writeFile(new URL('rollout/preflight.sql', here), preflightSql, 'utf8');
console.log('wrote rollout/preflight.sql', preflightSql.length, 'bytes');

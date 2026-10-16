// Pure target guards for the opt-in real-PostgreSQL concurrency harness.
//
// No database connection happens here, so these rules are testable without an
// external environment. They exist because the harness creates and later drops
// auth/hocalist fixtures: an unvalidated target could destroy an unrelated
// local database.

export const LIVE_PROJECT_REF = 'icqwbzswokoulatomgql';
export const RESERVED_DATABASES = ['postgres', 'template0', 'template1'];
export const DISPOSABLE_NAME = /(test|disposable|scratch|tmp)/i;

export function concurrencySkipReason({ databaseUrl }) {
  return databaseUrl
    ? null
    : 'NOT RUN: set HOCALIST_TEST_DATABASE_URL to a disposable PostgreSQL instance';
}

export function assertConcurrencyTarget({ databaseUrl, acknowledged }) {
  if (!databaseUrl) throw new Error('HOCALIST_TEST_DATABASE_URL is not set');
  if (databaseUrl.includes(LIVE_PROJECT_REF) || /supabase\.co/i.test(databaseUrl)) {
    throw new Error('refusing the shared Supabase project; use a disposable PostgreSQL instance');
  }
  if (!acknowledged) {
    throw new Error('set HOCALIST_ALLOW_DISPOSABLE_DB=1 to confirm the target is disposable');
  }
  let parsed;
  try {
    parsed = new URL(databaseUrl);
  } catch {
    throw new Error('HOCALIST_TEST_DATABASE_URL is not a valid connection URL');
  }
  const database = decodeURIComponent(parsed.pathname.replace(/^\/+/, ''));
  if (!database) throw new Error('HOCALIST_TEST_DATABASE_URL must name a database');
  if (RESERVED_DATABASES.includes(database.toLowerCase())) {
    throw new Error(`refusing reserved database "${database}"; create a disposable database`);
  }
  if (!DISPOSABLE_NAME.test(database)) {
    throw new Error(
      `refusing database "${database}"; its name must contain test, disposable, scratch or tmp`,
    );
  }
  return { database, host: parsed.hostname };
}

export function assertEmptyTargetContents({
  schemas = [],
  publicRelations = 0,
  publicFunctions = 0,
}) {
  const issues = [];
  if (schemas.includes('hocalist')) issues.push('schema hocalist already exists');
  if (schemas.includes('auth')) issues.push('schema auth already exists');
  if (publicRelations > 0) issues.push(`public schema already has ${publicRelations} relation(s)`);
  if (publicFunctions > 0) issues.push(`public schema already has ${publicFunctions} function(s)`);
  if (issues.length > 0) {
    throw new Error(`refusing non-empty target before mutation: ${issues.join('; ')}`);
  }
}

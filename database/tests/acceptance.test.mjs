// Opt-in synthetic real-API acceptance harness for the account backend.
//
// PREPARED, NOT EXECUTED. It never creates users, never sends email/SMS and
// never uses the service role. It only exercises REST/RPC calls with access
// tokens an operator has already provisioned for synthetic identities on a
// disposable target project.
//
// Required environment:
//   HOCALIST_ACCEPTANCE_URL=https://<disposable-project>.supabase.co
//   HOCALIST_ACCEPTANCE_ANON_KEY=<publishable anon key>
//   HOCALIST_ACCEPTANCE_ALLOW=1
// Optional (tests skip when absent):
//   HOCALIST_ACCEPTANCE_TOKEN_A=<synthetic identity A access token>
//   HOCALIST_ACCEPTANCE_TOKEN_B=<synthetic identity B access token>
//   HOCALIST_ACCEPTANCE_TOKEN_RESTRICTED=<restricted identity access token>
//
// The harness refuses the shared live project. Run with:
//   npm run test:acceptance
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const baseUrl = (process.env.HOCALIST_ACCEPTANCE_URL ?? '').replace(/\/+$/, '');
const anonKey = process.env.HOCALIST_ACCEPTANCE_ANON_KEY ?? '';
const allow = process.env.HOCALIST_ACCEPTANCE_ALLOW === '1';
const tokenA = process.env.HOCALIST_ACCEPTANCE_TOKEN_A ?? '';
const tokenB = process.env.HOCALIST_ACCEPTANCE_TOKEN_B ?? '';
const tokenRestricted = process.env.HOCALIST_ACCEPTANCE_TOKEN_RESTRICTED ?? '';
const LIVE_REF = 'icqwbzswokoulatomgql';

const configured = Boolean(baseUrl && anonKey);
let guardError = null;
if (configured && baseUrl.includes(LIVE_REF)) {
  guardError = new Error('refusing the shared live Supabase project; use a disposable project');
} else if (configured && !allow) {
  guardError = new Error('set HOCALIST_ACCEPTANCE_ALLOW=1 to acknowledge synthetic test data');
}

const rest = async (path, { token, method = 'GET', body, prefer } = {}) => {
  const headers = {
    apikey: anonKey,
    'Accept-Profile': 'hocalist',
    'Content-Profile': 'hocalist',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (prefer) headers.Prefer = prefer;
  const response = await fetch(`${baseUrl}/rest/v1/${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: response.status, json, text };
};

const rpc = (token, operation, key, input) =>
  rest('rpc/account_command', {
    token,
    method: 'POST',
    body: { p_operation: operation, p_key: key, p_input: input },
  });

const jwtSub = (token) =>
  JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8')).sub;

const deniedStatuses = [401, 403, 404];

const runAcceptance = async (t) => {
  const uidA = tokenA ? jwtSub(tokenA) : null;
  const uidB = tokenB ? jwtSub(tokenB) : null;

  await t.test('anonymous access is denied', async () => {
    const select = await rest('memberships?select=id,user_id,role,status');
    assert.ok(deniedStatuses.includes(select.status), `anon select: ${select.status}`);
    const command = await rpc('', 'onboard', `anon-${randomUUID()}`, {
      role: 'buyer', display_name: 'Anon',
    });
    assert.ok(deniedStatuses.includes(command.status), `anon rpc: ${command.status}`);
  });

  await t.test('identity A reads only its own account rows', { skip: !tokenA && 'set HOCALIST_ACCEPTANCE_TOKEN_A' }, async () => {
    const own = await rest('memberships?select=id,user_id,role,status&order=role', { token: tokenA });
    assert.equal(own.status, 200, own.text);
    assert.ok(Array.isArray(own.json));
    for (const row of own.json) assert.equal(row.user_id, uidA);

    const guessed = await rest(`memberships?select=id&user_id=eq.${uidB ?? randomUUID()}`, { token: tokenA });
    assert.equal(guessed.status, 200, guessed.text);
    assert.deepEqual(guessed.json, []);

    const contacts = await rest('profile_contacts?select=user_id,phone', { token: tokenA });
    assert.equal(contacts.status, 200, contacts.text);
    for (const row of contacts.json) assert.equal(row.user_id, uidA);
  });

  await t.test('direct client writes are denied', { skip: !tokenA && 'set HOCALIST_ACCEPTANCE_TOKEN_A' }, async () => {
    const insert = await rest('memberships', {
      token: tokenA,
      method: 'POST',
      body: { user_id: uidA, role: 'seller', status: 'active' },
      prefer: 'return=minimal',
    });
    assert.ok(deniedStatuses.includes(insert.status), `insert: ${insert.status}`);
    const update = await rest(`memberships?user_id=eq.${uidA}`, {
      token: tokenA,
      method: 'PATCH',
      body: { status: 'disabled' },
      prefer: 'return=minimal',
    });
    assert.ok(deniedStatuses.includes(update.status), `update: ${update.status}`);
    const del = await rest(`memberships?user_id=eq.${uidA}`, {
      token: tokenA,
      method: 'DELETE',
      prefer: 'return=minimal',
    });
    assert.ok(deniedStatuses.includes(del.status), `delete: ${del.status}`);
  });

  await t.test('mass assignment and forged ownership are rejected', { skip: !tokenA && 'set HOCALIST_ACCEPTANCE_TOKEN_A' }, async () => {
    const adminRole = await rpc(tokenA, 'onboard', `admin-${randomUUID()}`, {
      role: 'admin', display_name: 'Forged',
    });
    assert.equal(adminRole.status, 400, adminRole.text);
    assert.equal(adminRole.json?.code, '22023');

    const unknown = await rpc(tokenA, 'onboard', `unknown-${randomUUID()}`, {
      role: 'buyer', display_name: 'Forged', status: 'active',
    });
    assert.equal(unknown.status, 400, unknown.text);
    assert.equal(unknown.json?.code, '22023');

    const forged = await rpc(tokenA, 'profile.update', `forged-${randomUUID()}`, {
      profile_id: randomUUID(), expected_revision: 1, display_name: 'Forged',
    });
    assert.equal(forged.status, 403, forged.text);
    assert.equal(forged.json?.code, '42501');
  });

  await t.test('onboarding, replay and revision conflicts behave as documented', { skip: !tokenA && 'set HOCALIST_ACCEPTANCE_TOKEN_A' }, async () => {
    const key = `acceptance-${randomUUID()}`;
    const input = { role: 'buyer', display_name: 'Acceptance Buyer' };
    const first = await rpc(tokenA, 'onboard', key, input);
    if (first.status === 409) {
      // Identity already has a buyer membership; the operator must provision a
      // fresh synthetic identity to exercise creation.
      assert.equal(first.json?.code, 'P0001');
      return;
    }
    assert.equal(first.status, 200, first.text);
    const stored = first.json;
    assert.deepEqual(Object.keys(stored).sort(), ['profile_id', 'revision', 'role']);

    const replay = await rpc(tokenA, 'onboard', key, input);
    assert.equal(replay.status, 200, replay.text);
    assert.deepEqual(replay.json, stored);

    const conflict = await rpc(tokenA, 'onboard', key, { ...input, display_name: 'Changed' });
    assert.equal(conflict.status, 409, conflict.text);
    assert.equal(conflict.json?.code, 'P0001');
    assert.match(conflict.json?.message ?? '', /idempotency_conflict/);

    const update = await rpc(tokenA, 'profile.update', `acceptance-update-${randomUUID()}`, {
      profile_id: stored.profile_id, expected_revision: stored.revision, display_name: 'Acceptance v2',
    });
    assert.equal(update.status, 200, update.text);
    assert.equal(update.json.revision, stored.revision + 1);

    const stale = await rpc(tokenA, 'profile.update', `acceptance-stale-${randomUUID()}`, {
      profile_id: stored.profile_id, expected_revision: stored.revision, display_name: 'Stale',
    });
    assert.equal(stale.status, 409, stale.text);
    assert.match(stale.json?.message ?? '', /revision_conflict/);
  });

  await t.test('identity B is isolated from A', { skip: !tokenB && 'set HOCALIST_ACCEPTANCE_TOKEN_B' }, async () => {
    const own = await rest('memberships?select=id,user_id,role,status', { token: tokenB });
    assert.equal(own.status, 200, own.text);
    for (const row of own.json) assert.equal(row.user_id, uidB);
    const guessed = await rest(`memberships?select=id&user_id=eq.${uidA ?? randomUUID()}`, { token: tokenB });
    assert.equal(guessed.status, 200, guessed.text);
    assert.deepEqual(guessed.json, []);
  });

  await t.test('restricted identity is blocked', { skip: !tokenRestricted && 'set HOCALIST_ACCEPTANCE_TOKEN_RESTRICTED' }, async () => {
    const command = await rpc(tokenRestricted, 'contact.update', `restricted-${randomUUID()}`, {
      expected_revision: 1, city: 'Blocked',
    });
    assert.equal(command.status, 403, command.text);
    assert.equal(command.json?.code, '42501');
    assert.match(command.json?.message ?? '', /account_restricted/);
  });
};

if (guardError) {
  test('synthetic real-API account acceptance', () => {
    throw guardError;
  });
} else {
  test(
    'synthetic real-API account acceptance',
    { skip: !configured && 'NOT RUN: set HOCALIST_ACCEPTANCE_URL and HOCALIST_ACCEPTANCE_ANON_KEY' },
    runAcceptance,
  );
}

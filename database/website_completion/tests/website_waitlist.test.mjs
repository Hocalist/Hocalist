// Disposable PostgreSQL checks for the consented public waitlist. Proves the
// server-controlled intake boundary: deployment secret required, admission
// budget counted separately from stored consent rows (so known and unknown
// addresses are indistinguishable across request sequences), duplicate-safe
// persistence and no timestamp oracle. PGlite is local single-connection
// proof; its advisory locks serialize statements, so true multi-connection
// concurrency is not reproduced here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { applySignupSeed, createDisposableDb } from '../../tests/fixture.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');
const TOKEN = 'waitlist-intake-token-0123456789abcdefghijklmnopqrstuvwxyz';
const HASH_A = 'a'.repeat(64);
const HASH_B = 'b'.repeat(64);

async function asRole(db, role, body) {
  await db.exec(`SET ROLE ${role}`);
  try {
    return await body();
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function join(db, email, options = {}) {
  const {
    consent = 'launch-updates-v1',
    source = 'download-page',
    hash = HASH_A,
    token = TOKEN,
  } = options;
  return asRole(db, 'anon', async () =>
    (await db.query(
      'SELECT hocalist.website_waitlist_join($1,$2,$3,$4,$5) AS data',
      [email, consent, source, hash, token],
    )).rows[0].data);
}

async function configure(db, token = TOKEN) {
  await asRole(db, 'service_role', async () => {
    await db.query('SELECT hocalist.website_waitlist_configure($1)', [token]);
  });
}

async function setCaps(db, perFingerprint, global) {
  await asRole(db, 'service_role', async () => {
    await db.query('SELECT hocalist.website_waitlist_set_caps($1,$2)', [perFingerprint, global]);
  });
}

async function expectRejected(promise, messagePart, code = 'P0001') {
  try {
    await promise;
  } catch (error) {
    assert.equal(error.code, code, `${messagePart}: got ${error.code} ${error.message}`);
    assert.match(error.message, new RegExp(messagePart));
    return error;
  }
  assert.fail(`expected SQLSTATE ${code} for ${messagePart}`);
}

async function sequenceResult(db, email, hash) {
  try {
    await join(db, email, { hash });
    return 'ok';
  } catch {
    return 'rejected';
  }
}

test('waitlist intake is a server-controlled boundary with generic results', async (t) => {
  const db = await createDisposableDb();
  try {
    await applySignupSeed(db);
    await db.exec(await read('../170_website_waitlist.sql'));

    await t.test('an unconfigured deployment stores nothing', async () => {
      await expectRejected(join(db, 'buyer@example.com'), 'waitlist_not_configured');
      const rows = await db.query('SELECT count(*)::int AS n FROM hocalist.website_waitlist_signups');
      assert.equal(rows.rows[0].n, 0);
    });

    await t.test('only the service role can set or rotate the intake secret', async () => {
      for (const role of ['anon', 'authenticated']) {
        await asRole(db, role, async () => {
          await expectRejected(
            db.query('SELECT hocalist.website_waitlist_configure($1)', [TOKEN]),
            'permission denied',
            '42501',
          );
        });
      }
      await expectRejected(
        asRole(db, 'service_role', async () => {
          await db.query('SELECT hocalist.website_waitlist_configure($1)', ['too-short']);
        }),
        'invalid_intake_token',
        '22023',
      );
      await configure(db);
    });

    await t.test('a public caller cannot join without the deployment secret', async () => {
      await expectRejected(join(db, 'buyer@example.com', { token: null }), 'invalid_intake', '42501');
      await expectRejected(
        join(db, 'buyer@example.com', { token: 'x'.repeat(40) }),
        'invalid_intake',
        '42501',
      );
      for (let index = 0; index < 6; index++) {
        await expectRejected(
          join(db, `invented${index}@example.com`, { hash: String(index).repeat(64).slice(0, 64), token: null }),
          'invalid_intake',
          '42501',
        );
      }
      const rows = await db.query('SELECT count(*)::int AS n FROM hocalist.website_waitlist_signups');
      assert.equal(rows.rows[0].n, 0);
    });

    await t.test('a duplicate is idempotent, keeps consent and never exposes a timestamp', async () => {
      assert.deepEqual(await join(db, ' Buyer@Example.COM '), { status: 'joined' });
      const stored = (await db.query(
        "SELECT consented_at FROM hocalist.website_waitlist_signups WHERE email_normalized='buyer@example.com'"))
        .rows[0].consented_at;
      const again = await join(db, 'buyer@example.com');
      assert.deepEqual(again, { status: 'already_joined' });
      assert.equal(Object.hasOwn(again, 'consented_at'), false);
      const rows = await db.query(
        'SELECT email, email_normalized, consent_version, source, consented_at FROM hocalist.website_waitlist_signups');
      assert.equal(rows.rows.length, 1);
      assert.equal(rows.rows[0].email, 'Buyer@Example.COM');
      assert.equal(rows.rows[0].email_normalized, 'buyer@example.com');
      assert.equal(rows.rows[0].consent_version, 'launch-updates-v1');
      assert.equal(rows.rows[0].source, 'download-page');
      assert.deepEqual(rows.rows[0].consented_at, stored, 'a repeat never rewrites the consent record');
    });

    await t.test('invalid input is refused server-side even with the secret', async () => {
      await expectRejected(join(db, 'not-an-email'), 'invalid_email', '22023');
      await expectRejected(join(db, 'ok@example.com', { consent: 'other' }), 'consent_required', '22023');
      await expectRejected(join(db, 'ok@example.com', { hash: 'short' }), 'invalid_client', '22023');
      await expectRejected(join(db, 'ok@example.com', { source: 'x'.repeat(81) }), 'invalid_source', '22023');
      const rows = await db.query('SELECT count(*)::int AS n FROM hocalist.website_waitlist_signups');
      assert.equal(rows.rows[0].n, 1);
    });

    await t.test('every admitted submission consumes admission budget, new or duplicate', async () => {
      const hash = 'c'.repeat(64);
      assert.deepEqual(await join(db, 'budget@example.com', { hash }), { status: 'joined' });
      for (let index = 0; index < 4; index++) {
        const expected = index === 0
          ? { status: 'already_joined' }
          : { status: 'joined' };
        assert.deepEqual(
          await join(db, index === 0 ? 'budget@example.com' : `budget${index}@example.com`, { hash }),
          expected,
        );
      }
      // The budget is exhausted by the mix of duplicates and new addresses.
      await expectRejected(join(db, 'budget@example.com', { hash }), 'rate_limited');
      await expectRejected(join(db, 'budget-new@example.com', { hash }), 'rate_limited');
      const admissions = (await db.query(
        'SELECT admitted FROM hocalist.website_waitlist_admissions WHERE client_hash=$1', [hash])).rows[0];
      assert.equal(admissions.admitted, 5);
      const signups = (await db.query(
        "SELECT count(*)::int AS n FROM hocalist.website_waitlist_signups WHERE client_hash=$1", [hash])).rows[0];
      assert.equal(signups.n, 4, 'the duplicate added no second signup row');
    });

    await t.test('known and unknown targets produce identical sequences from equal admission states', async () => {
      // Two baselines of equal size differ only in whether the target address
      // is already stored (seeded directly, so it consumes no admission
      // budget). Each sequence starts from a fresh admission state, so the
      // admissibility sequence must not differ.
      const runSequence = async (targetRegistered, hash) => {
        const fixtureHash = targetRegistered ? 'f'.repeat(64) : '7'.repeat(64);
        const targetEmail = targetRegistered ? 'target-seq-a@example.com' : 'target-seq-b@example.com';
        const fixtureEmail = targetRegistered ? targetEmail : 'unrelated-seq-b@example.com';
        await db.query(
          `INSERT INTO hocalist.website_waitlist_signups(email,email_normalized,consent_version,source,client_hash)
           VALUES ($1,$1,'launch-updates-v1','fixture',$2)
           ON CONFLICT(email_normalized) DO NOTHING`,
          [fixtureEmail, fixtureHash]);
        const outcomes = [];
        for (let index = 0; index < 4; index++) {
          outcomes.push(await sequenceResult(db, `seq-${index}-${targetRegistered}@example.com`, hash));
        }
        const target = await join(db, targetEmail, { hash });
        outcomes.push('ok');
        outcomes.push(await sequenceResult(db, `after-${targetRegistered}@example.com`, hash));
        return { outcomes, targetStatus: target.status };
      };
      const withTarget = await runSequence(true, '1'.repeat(64));
      const withoutTarget = await runSequence(false, '2'.repeat(64));
      assert.deepEqual(withTarget.outcomes, withoutTarget.outcomes, 'admissibility is membership-independent');
      assert.deepEqual(withTarget.outcomes, ['ok', 'ok', 'ok', 'ok', 'ok', 'rejected'],
        'the sequence is limited only by the shared admission budget');
      assert.equal(withTarget.targetStatus, 'already_joined');
      assert.equal(withoutTarget.targetStatus, 'joined');
    });

    await t.test('per-fingerprint and global caps refuse known and unknown addresses equally', async () => {
      const cappedHash = 'd'.repeat(64);
      for (let index = 0; index < 5; index++) {
        assert.deepEqual(await join(db, `cap${index}@example.com`, { hash: cappedHash }), { status: 'joined' });
      }
      await expectRejected(join(db, 'cap0@example.com', { hash: cappedHash }), 'rate_limited');
      await expectRejected(join(db, 'cap-new@example.com', { hash: cappedHash }), 'rate_limited');

      const windowAdmissions = (await db.query(
        'SELECT coalesce(sum(admitted),0)::int AS n FROM hocalist.website_waitlist_admissions')).rows[0].n;
      await setCaps(db, 50, windowAdmissions);
      await expectRejected(join(db, 'buyer@example.com', { hash: 'e'.repeat(64) }), 'rate_limited');
      await expectRejected(join(db, 'unknown-global@example.com', { hash: 'e'.repeat(64) }), 'rate_limited');
      await setCaps(db, 5, 240);
      assert.deepEqual(
        await join(db, 'unknown-global@example.com', { hash: 'e'.repeat(64) }),
        { status: 'joined' },
      );
      assert.deepEqual(await join(db, 'buyer@example.com', { hash: HASH_B }), { status: 'already_joined' });
    });

    await t.test('stale admission windows are pruned so the ledger stays bounded', async () => {
      const staleHash = '9'.repeat(64);
      await db.query(
        `INSERT INTO hocalist.website_waitlist_admissions(client_hash,window_start,admitted)
         VALUES ($1, now() - interval '5 hours', 5)`, [staleHash]);
      assert.deepEqual(await join(db, 'pruned@example.com', { hash: '8'.repeat(64) }), { status: 'joined' });
      const stale = await db.query(
        'SELECT count(*)::int AS n FROM hocalist.website_waitlist_admissions WHERE client_hash=$1', [staleHash]);
      assert.equal(stale.rows[0].n, 0);
    });

    await t.test('no client role can read the list, the admissions or the configuration', async () => {
      for (const role of ['anon', 'authenticated', 'service_role']) {
        for (const table of [
          'hocalist.website_waitlist_signups',
          'hocalist.website_waitlist_admissions',
          'hocalist.website_waitlist_config',
        ]) {
          await asRole(db, role, async () => {
            await expectRejected(
              db.query(`SELECT count(*) FROM ${table}`),
              'permission denied',
              '42501',
            );
          });
        }
      }
    });
  } finally {
    await db.close();
  }
});

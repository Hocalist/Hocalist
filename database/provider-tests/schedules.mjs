import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../tests/node_modules/@electric-sql/pglite/dist/index.js';

const rollout = await readFile(new URL('../provider-rollout/paused_schedules.sql', import.meta.url), 'utf8');
test('scheduler transaction creates only paused jobs and refuses duplicates or missing credentials', async () => {
  const db = new PGlite();
  try {
    // Mock extension APIs only. This proves transaction/command assembly, not pg_cron execution.
    await db.exec(`
      CREATE SCHEMA cron; CREATE SCHEMA vault;
      CREATE TABLE vault.decrypted_secrets(name text, decrypted_secret text);
      CREATE TABLE cron.job(jobid bigserial, jobname text UNIQUE, schedule text,
        command text, active boolean DEFAULT true, username text DEFAULT current_user);
      CREATE FUNCTION cron.schedule(job_name text, schedule text, command text) RETURNS bigint
      LANGUAGE sql AS 'INSERT INTO cron.job(jobname,schedule,command) VALUES ($1,$2,$3) RETURNING jobid';
      CREATE FUNCTION cron.alter_job(job_id bigint, active boolean) RETURNS void
      LANGUAGE sql AS 'UPDATE cron.job SET active=$2 WHERE jobid=$1';
      INSERT INTO cron.job(jobname,schedule,command) VALUES ('unrelated','0 * * * *','SELECT 1');
    `);
    await assert.rejects(db.exec(rollout), /Missing or invalid/);
    await db.exec('ROLLBACK');
    assert.equal((await db.query('SELECT count(*)::int AS n FROM cron.job')).rows[0].n,1);
    await db.query('INSERT INTO vault.decrypted_secrets VALUES ($1,$2),($3,$4)',[
      'hocalist_stripe_test_worker_secret','a'.repeat(64),
      'hocalist_push_worker_secret','b'.repeat(64),
    ]);
    await db.exec(rollout);
    const jobs=(await db.query("SELECT * FROM cron.job WHERE jobname LIKE 'hocalist%' ORDER BY jobname")).rows;
    assert.equal(jobs.length,2);
    for(const job of jobs){
      assert.equal(job.active,false);
      assert.equal(job.schedule,'* * * * *');
      assert.equal(job.username,'postgres');
      assert.ok(job.command.includes('vault.decrypted_secrets'));
      assert.ok(!job.command.includes('a'.repeat(64)) && !job.command.includes('b'.repeat(64)));
      assert.ok(job.command.includes('https://icqwbzswokoulatomgql.supabase.co/functions/v1/'));
    }
    assert.equal((await db.query("SELECT active FROM cron.job WHERE jobname='unrelated'")).rows[0].active,true);
    await assert.rejects(db.exec(rollout), /already exist/);
    await db.exec('ROLLBACK');
    assert.deepEqual((await db.query("SELECT * FROM cron.job WHERE jobname LIKE 'hocalist%' ORDER BY jobname")).rows,jobs);
  } finally { await db.close(); }
});

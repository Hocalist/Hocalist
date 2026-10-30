import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../../public-web/node_modules/@electric-sql/pglite/dist/index.js';
const sql=await readFile(new URL('./elite_settlement_schedule.sql',import.meta.url),'utf8');
async function setup(present=true){
 const db=new PGlite();
 await db.exec(`CREATE SCHEMA cron; CREATE SCHEMA hocalist;
 CREATE TABLE cron.job(jobid bigint GENERATED ALWAYS AS IDENTITY,jobname text,schedule text,command text,active boolean DEFAULT true);
 CREATE FUNCTION cron.schedule(n text,s text,c text) RETURNS bigint LANGUAGE SQL AS 'INSERT INTO cron.job(jobname,schedule,command) VALUES(n,s,c) RETURNING jobid';
 CREATE FUNCTION cron.alter_job(j bigint,active boolean) RETURNS void LANGUAGE SQL AS 'UPDATE cron.job SET active=$2 WHERE jobid=j';`);
 if(present)await db.exec('CREATE FUNCTION hocalist.credit_elite_due_sweep(integer) RETURNS integer LANGUAGE SQL AS $$ SELECT 0 $$');
 return db;
}
test('Elite job installs paused, bounded, without credentials or provider calls',async()=>{
 const db=await setup();try{
  await db.exec(sql);const [j]=(await db.query('SELECT * FROM cron.job')).rows;
  assert.equal(j.active,false);assert.equal(j.schedule,'*/5 * * * *');assert.equal(j.command,'SELECT hocalist.credit_elite_due_sweep(200);');
  await assert.rejects(db.exec(sql),/already exists/);await db.exec('ROLLBACK');assert.equal((await db.query('SELECT count(*) n FROM cron.job')).rows[0].n,1);
 }finally{await db.close();}
});
test('missing timing repair refuses installation',async()=>{
 const db=await setup(false);try{await assert.rejects(db.exec(sql),/repair missing/);await db.exec('ROLLBACK');assert.equal((await db.query('SELECT count(*) n FROM cron.job')).rows[0].n,0);}finally{await db.close();}
});

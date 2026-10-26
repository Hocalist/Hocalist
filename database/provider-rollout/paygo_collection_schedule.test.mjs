import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../../public-web/node_modules/@electric-sql/pglite/dist/index.js';
const sql=await readFile(new URL('./paygo_collection_schedule.sql',import.meta.url),'utf8');
async function setup(secret='a'.repeat(64)){
 const db=new PGlite();
 await db.exec(`CREATE SCHEMA cron; CREATE SCHEMA vault;
 CREATE TABLE cron.job(jobid bigint GENERATED ALWAYS AS IDENTITY,jobname text,schedule text,command text,active boolean DEFAULT true);
 CREATE TABLE vault.decrypted_secrets(name text,decrypted_secret text);
 CREATE FUNCTION cron.schedule(n text,s text,c text) RETURNS bigint LANGUAGE SQL AS 'INSERT INTO cron.job(jobname,schedule,command) VALUES(n,s,c) RETURNING jobid';
 CREATE FUNCTION cron.alter_job(j bigint,active boolean) RETURNS void LANGUAGE SQL AS 'UPDATE cron.job SET active=$2 WHERE jobid=j';`);
 if(secret!==null)await db.query('INSERT INTO vault.decrypted_secrets VALUES($1,$2)',['hocalist_paygo_worker_secret',secret]);
 return db;
}
test('dedicated job installs paused with runtime policy gate and no inline credential',async()=>{
 const db=await setup();try{await db.exec(sql);const {rows:[r]}=await db.query('SELECT * FROM cron.job');
 assert.equal(r.active,false);assert.equal(r.schedule,'* * * * *');
 assert.match(r.command,/WHERE \(SELECT enabled FROM hocalist.paygo_collection_policy/);
 assert.match(r.command,/hocalist-paygo-collect/);assert.doesNotMatch(r.command,/a{64}/);
 await assert.rejects(db.exec(sql),/already exists/);await db.exec('ROLLBACK');
 assert.equal((await db.query('SELECT count(*) n FROM cron.job')).rows[0].n,1);
 }finally{await db.close();}
});
for(const secret of [null,'short'])test(`missing or invalid credential refuses installation (${secret})`,async()=>{
 const db=await setup(secret);try{await assert.rejects(db.exec(sql),/missing or invalid/);await db.exec('ROLLBACK');assert.equal((await db.query('SELECT count(*) n FROM cron.job')).rows[0].n,0);}finally{await db.close();}
});

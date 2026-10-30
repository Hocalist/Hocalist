-- Separate approval to activate is required. Installs one paused database job.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $install$
DECLARE job_id bigint;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('hocalist:elite_due_schedule',0));
 IF to_regprocedure('hocalist.credit_elite_due_sweep(integer)') IS NULL THEN RAISE EXCEPTION 'Elite timing repair missing'; END IF;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='hocalist-elite-due-settlement') THEN RAISE EXCEPTION 'Elite schedule already exists; inspect before changing'; END IF;
 job_id:=cron.schedule('hocalist-elite-due-settlement','*/5 * * * *','SELECT hocalist.credit_elite_due_sweep(200);');
 PERFORM cron.alter_job(job_id,active:=false);
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=job_id AND NOT active) THEN RAISE EXCEPTION 'Elite schedule must install paused'; END IF;
END $install$;
COMMIT;

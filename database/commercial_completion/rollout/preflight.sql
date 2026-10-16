BEGIN READ ONLY;
DO $guard$ BEGIN
IF to_regprocedure('hocalist.withdrawal_available_minor(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.withdrawal_available_minor(uuid)')),chr(13),''))<>'4123a66f1e85a86f2db301cc99c064a1' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.withdrawal_available_minor(uuid)'; END IF;
IF to_regprocedure('hocalist.withdrawal_request(text,bigint)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.withdrawal_request(text,bigint)')),chr(13),''))<>'56d70610f58760eda3c7ca76f15706fe' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.withdrawal_request(text,bigint)'; END IF;
IF to_regprocedure('hocalist.marketplace_seller_plan(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_seller_plan(uuid)')),chr(13),''))<>'4f5e6dec55d2e5f5a4ac560ce26a78bd' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_seller_plan(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_store_limit(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_store_limit(uuid)')),chr(13),''))<>'566cd5ebb44a0b335f267f79e2a43754' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_store_limit(uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_weekly_target_limit(uuid)')),chr(13),''))<>'c0f81ba7d560df4b3148897bfb9ac760' THEN RAISE EXCEPTION 'Prerequisite drift: hocalist.marketplace_weekly_target_limit(uuid)'; END IF;
IF to_regclass('hocalist.entitlement_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: entitlement_policy'; END IF;
IF to_regclass('hocalist.reconciliation_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reconciliation_policy'; END IF;
IF to_regclass('hocalist.reconciliation_runs') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reconciliation_runs'; END IF;
IF to_regclass('hocalist.reversal_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reversal_policy'; END IF;
IF to_regclass('hocalist.payment_reversals') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: payment_reversals'; END IF;
IF to_regclass('hocalist.ledger_corrections') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: ledger_corrections'; END IF;
IF to_regclass('hocalist.reversal_events') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: reversal_events'; END IF;
IF to_regclass('hocalist.payout_policy') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: payout_policy'; END IF;
IF to_regclass('hocalist.payout_attempts') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: payout_attempts'; END IF;
END $guard$;
ROLLBACK;

-- Initial fee is charged by successful offer submission, never by chat.
-- No historical target, balance, deposit rate or purchase total is rewritten.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)')
   AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('41bba13c5967bd5ca436b524d44934e2','6541227983a62e308dae9e9fb803f16f')
   AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
   RAISE EXCEPTION 'Offer fee definition drift: credit_authorize_target(uuid,uuid,uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)') AND a.privilege_type='EXECUTE'
   AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Offer fee helper grants drift: credit_authorize_target(uuid,uuid,uuid)'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.credit_qualify_conversation(uuid)')
   AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('5121b0b05fa9eb2dec06d22f4356c92e','58bfa4a6866674fc3af8f42290c89007')
   AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
   RAISE EXCEPTION 'Offer fee definition drift: credit_qualify_conversation(uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure('hocalist.credit_qualify_conversation(uuid)') AND a.privilege_type='EXECUTE'
   AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Offer fee helper grants drift: credit_qualify_conversation(uuid)'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.conversation_messages'::regclass
   AND tgname='chat_message_credit_qualify' AND NOT tgisinternal
   AND tgfoid IS DISTINCT FROM to_regprocedure('hocalist.chat_message_credit_qualify()')) THEN
   RAISE EXCEPTION 'Offer fee trigger drift'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION hocalist.credit_authorize_target(p_user uuid, p_request uuid, p_offer uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_week date := date_trunc('week', now() AT TIME ZONE 'UTC')::date;
  v_limit integer;
  v_id uuid;
  t hocalist.credit_targets%ROWTYPE;
  b hocalist.credit_batches%ROWTYPE;
BEGIN
  v_limit := coalesce(hocalist.marketplace_weekly_target_limit(p_user), 0);
  IF v_limit < 1 THEN
    RAISE EXCEPTION 'weekly_target_limit' USING ERRCODE='P0001';
  END IF;
  v_id := hocalist.credit_reserve_internal(p_user, p_request, p_offer, v_week, v_limit);
  -- Reserve and debit atomically inside the successful offer submission.
  -- The existing target/ledger lock makes command retries charge at most once.
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=v_id;
  IF t.status='reserved' THEN
    PERFORM hocalist.credit_settle_internal(v_id,'initial');
  END IF;
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=v_id;
  SELECT * INTO b FROM hocalist.credit_batches WHERE id=t.batch_id;
  RETURN jsonb_build_object('status',t.status,'target_id',t.id,'batch_id',b.id,
    'initial_fee_minor',t.initial_minor,'winning_total_minor',t.winning_minor,
    'rate_version',t.rate_version);
END $$;
CREATE OR REPLACE FUNCTION hocalist.credit_qualify_conversation(p_conversation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  -- Compatibility boundary only. Messages never debit an initial offer fee.
  -- Historical reservations are not charged retroactively by this migration.
  RETURN jsonb_build_object('status','not_chargeable');
END $$;
DROP TRIGGER IF EXISTS chat_message_credit_qualify ON hocalist.conversation_messages;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)')
   AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('6541227983a62e308dae9e9fb803f16f')
   AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
   RAISE EXCEPTION 'Offer fee definition drift: credit_authorize_target(uuid,uuid,uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure('hocalist.credit_authorize_target(uuid,uuid,uuid)') AND a.privilege_type='EXECUTE'
   AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Offer fee helper grants drift: credit_authorize_target(uuid,uuid,uuid)'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.credit_qualify_conversation(uuid)')
   AND md5(replace(prosrc,E'\r\n',E'\n')) IN ('58bfa4a6866674fc3af8f42290c89007')
   AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
   RAISE EXCEPTION 'Offer fee definition drift: credit_qualify_conversation(uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure('hocalist.credit_qualify_conversation(uuid)') AND a.privilege_type='EXECUTE'
   AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Offer fee helper grants drift: credit_qualify_conversation(uuid)'; END IF;
END $guard$;
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.conversation_messages'::regclass
  AND tgname='chat_message_credit_qualify' AND NOT tgisinternal) THEN
  RAISE EXCEPTION 'Message fee trigger remains'; END IF;
END $guard$;
COMMIT;

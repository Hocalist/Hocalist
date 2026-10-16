BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $guard$ BEGIN
IF to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)')),chr(13),''))<>'ab46a1b7b3c40c9ece49f082b1bbde21' THEN RAISE EXCEPTION 'Prerequisite function drift: hocalist.chat_assert_participant(uuid,uuid)'; END IF;
IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.marketplace_assert_admin(uuid)')),chr(13),''))<>'21180e7020200a2d299930b9f72e519f' THEN RAISE EXCEPTION 'Prerequisite function drift: hocalist.marketplace_assert_admin(uuid)'; END IF;
IF to_regprocedure('hocalist.meeting_assert_participant(uuid,uuid)') IS NULL OR md5(replace(pg_get_functiondef(to_regprocedure('hocalist.meeting_assert_participant(uuid,uuid)')),chr(13),''))<>'50e88d57d9c39f4c6b0c1a8f66b1515a' THEN RAISE EXCEPTION 'Prerequisite function drift: hocalist.meeting_assert_participant(uuid,uuid)'; END IF;
IF to_regclass('hocalist.buyer_rewards') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: buyer_rewards'; END IF;
IF to_regclass('hocalist.call_settings') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: call_settings'; END IF;
IF to_regclass('hocalist.call_settings_audit') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: call_settings_audit'; END IF;
IF to_regclass('hocalist.call_signals') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: call_signals'; END IF;
IF to_regclass('hocalist.calls') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: calls'; END IF;
IF to_regclass('hocalist.credit_batches') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: credit_batches'; END IF;
IF to_regclass('hocalist.credit_entries') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: credit_entries'; END IF;
IF to_regclass('hocalist.credit_targets') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: credit_targets'; END IF;
IF to_regclass('hocalist.media_images') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: media_images'; END IF;
IF to_regclass('hocalist.media_windows') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: media_windows'; END IF;
IF to_regclass('hocalist.request_pin_secrets') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: request_pin_secrets'; END IF;
IF to_regclass('hocalist.sale_confirmations') IS NOT NULL THEN RAISE EXCEPTION 'Already installed or partial installation: sale_confirmations'; END IF;
IF to_regprocedure('hocalist.call_admin_settings(boolean,bigint)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.call_admin_settings(boolean,bigint)'; END IF;
IF to_regprocedure('hocalist.call_command(text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.call_command(text,jsonb)'; END IF;
IF to_regprocedure('hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)'; END IF;
IF to_regprocedure('hocalist.credit_reserve_internal(uuid,uuid,date,integer)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.credit_reserve_internal(uuid,uuid,date,integer)'; END IF;
IF to_regprocedure('hocalist.credit_settle_internal(uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.credit_settle_internal(uuid,text)'; END IF;
IF to_regprocedure('hocalist.credit_wallet()') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.credit_wallet()'; END IF;
IF to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
IF to_regprocedure('hocalist.media_validate_references()') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.media_validate_references()'; END IF;
IF to_regprocedure('hocalist.reward_accrue_internal(uuid,uuid,bigint,text)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.reward_accrue_internal(uuid,uuid,bigint,text)'; END IF;
IF to_regprocedure('hocalist.reward_wallet()') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.reward_wallet()'; END IF;
IF to_regprocedure('hocalist.sale_history(timestamp with time zone,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.sale_history(timestamp with time zone,uuid)'; END IF;
IF to_regprocedure('hocalist.sale_keep_final()') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.sale_keep_final()'; END IF;
IF to_regprocedure('hocalist.sale_pin(uuid,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.sale_pin(uuid,text,text)'; END IF;
IF to_regprocedure('hocalist.sale_pin_digits(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'Function already exists: hocalist.sale_pin_digits(uuid)'; END IF;
END $guard$;
-- Local migration: request-owned sale confirmation. No money movement.

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$ BEGIN
 IF to_regprocedure('hocalist.meeting_assert_participant(uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'meeting foundation missing';
 END IF;
 IF to_regclass('hocalist.sale_confirmations') IS NOT NULL THEN
  RAISE EXCEPTION 'sale confirmation already installed';
 END IF;
END $$;
CREATE TABLE hocalist.request_pin_secrets (
 request_id uuid PRIMARY KEY REFERENCES hocalist.requests(id),
 meeting_id uuid NOT NULL REFERENCES hocalist.meetings(id),
 schedule_revision_id uuid NOT NULL,
 secret uuid NOT NULL DEFAULT gen_random_uuid(),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 window_attempts integer NOT NULL DEFAULT 0 CHECK(window_attempts>=0),
 locked_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE hocalist.sale_confirmations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL UNIQUE REFERENCES hocalist.requests(id),
 meeting_id uuid NOT NULL REFERENCES hocalist.meetings(id),
 offer_id uuid NOT NULL REFERENCES hocalist.offers(id),
 schedule_revision_id uuid NOT NULL,
 buyer_user_id uuid NOT NULL,
 seller_user_id uuid NOT NULL,
 confirmed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.request_pin_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.sale_confirmations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.request_pin_secrets,hocalist.sale_confirmations FROM PUBLIC,anon,authenticated,service_role;

-- Derive display digits from a private random secret; neither plaintext PIN
-- nor attempted PIN is persisted or included in receipts/log messages.
CREATE FUNCTION hocalist.sale_pin_digits(p_secret uuid) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT lpad(((('x'||substr(encode(sha256(convert_to(p_secret::text,'UTF8')),'hex'),1,12))::bit(48)::bigint)%100000)::text,5,'0')
$$;

CREATE FUNCTION hocalist.sale_pin(p_meeting uuid,p_action text,p_pin text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); m hocalist.meetings%ROWTYPE;
 s hocalist.request_pin_secrets%ROWTYPE; outcome hocalist.sale_confirmations%ROWTYPE;
BEGIN
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 IF p_action NOT IN ('display','verify','status') OR p_action IS NULL THEN
  RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
 END IF;
 IF (p_action='display' AND u<>m.buyer_user_id) OR (p_action='verify' AND u<>m.seller_user_id) THEN
  RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501';
 END IF;
 -- Match marketplace lock order; serialize all sellers for the request.
 PERFORM 1 FROM hocalist.requests WHERE id=m.request_id FOR UPDATE;
 PERFORM 1 FROM hocalist.meetings WHERE id=p_meeting FOR UPDATE;
 m:=hocalist.meeting_assert_participant(p_meeting,u);
 SELECT * INTO outcome FROM hocalist.sale_confirmations WHERE request_id=m.request_id;
 IF FOUND THEN
  IF outcome.meeting_id<>p_meeting THEN RETURN jsonb_build_object('status','completed_elsewhere'); END IF;
  RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
 END IF;
 IF p_action='status' THEN RETURN jsonb_build_object('status','unconfirmed'); END IF;
 IF m.status<>'accepted' OR m.accepted_revision_id IS NULL THEN
  RETURN jsonb_build_object('status','meeting_not_accepted');
 END IF;
 IF m.meeting_expires_at IS NULL OR now()>=m.meeting_expires_at THEN
  RETURN jsonb_build_object('status','expired');
 END IF;
 IF p_action='display' THEN
  INSERT INTO hocalist.request_pin_secrets(request_id,meeting_id,schedule_revision_id)
   VALUES(m.request_id,m.id,m.accepted_revision_id)
   ON CONFLICT(request_id) DO UPDATE SET meeting_id=excluded.meeting_id,
    schedule_revision_id=excluded.schedule_revision_id,secret=gen_random_uuid()
   WHERE request_pin_secrets.meeting_id<>excluded.meeting_id
      OR request_pin_secrets.schedule_revision_id<>excluded.schedule_revision_id;
  SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
  RETURN jsonb_build_object('status','ready','pin',hocalist.sale_pin_digits(s.secret),'expires_at',m.meeting_expires_at);
 END IF;
 SELECT * INTO s FROM hocalist.request_pin_secrets WHERE request_id=m.request_id FOR UPDATE;
 IF NOT FOUND OR s.meeting_id<>m.id OR s.schedule_revision_id<>m.accepted_revision_id THEN
  RETURN jsonb_build_object('status','buyer_must_open_pin');
 END IF;
 IF s.attempts>=30 THEN RETURN jsonb_build_object('status','support_required'); END IF;
 IF s.locked_until>now() THEN RETURN jsonb_build_object('status','locked','retry_at',s.locked_until); END IF;
 IF p_pin IS NULL OR p_pin!~'^[0-9]{5}$' THEN RETURN jsonb_build_object('status','invalid_format'); END IF;
 IF s.locked_until IS NOT NULL THEN s.window_attempts:=0; END IF;
 IF p_pin<>hocalist.sale_pin_digits(s.secret) THEN
  UPDATE hocalist.request_pin_secrets SET attempts=attempts+1,
   window_attempts=s.window_attempts+1,
   locked_until=CASE WHEN s.window_attempts+1>=5 THEN now()+interval '15 minutes' ELSE NULL END
   WHERE request_id=m.request_id;
  -- A returned failure, not an exception: failed attempts must COMMIT.
  RETURN jsonb_build_object('status',CASE WHEN s.window_attempts+1>=5 THEN 'locked' ELSE 'incorrect' END);
 END IF;
 INSERT INTO hocalist.sale_confirmations(request_id,meeting_id,offer_id,schedule_revision_id,buyer_user_id,seller_user_id)
  VALUES(m.request_id,m.id,m.offer_id,m.accepted_revision_id,m.buyer_user_id,m.seller_user_id) RETURNING * INTO outcome;
 UPDATE hocalist.requests SET status='closed',revision=revision+1,updated_at=now() WHERE id=m.request_id;
 DELETE FROM hocalist.request_pin_secrets WHERE request_id=m.request_id;
 RETURN jsonb_build_object('status','confirmed','outcome_id',outcome.id,'confirmed_at',outcome.confirmed_at);
END $$;

CREATE FUNCTION hocalist.sale_keep_final() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_TABLE_NAME='meetings' THEN
  IF EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE meeting_id=OLD.id) THEN
   RAISE EXCEPTION 'sale_already_confirmed' USING ERRCODE='P0001';
  END IF;
 ELSIF NEW.status<>'closed' AND EXISTS(SELECT 1 FROM hocalist.sale_confirmations WHERE request_id=OLD.id) THEN
  RAISE EXCEPTION 'sale_already_confirmed' USING ERRCODE='P0001';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER sale_final_meeting BEFORE UPDATE ON hocalist.meetings FOR EACH ROW EXECUTE FUNCTION hocalist.sale_keep_final();
CREATE TRIGGER sale_final_request BEFORE UPDATE ON hocalist.requests FOR EACH ROW EXECUTE FUNCTION hocalist.sale_keep_final();
REVOKE ALL ON FUNCTION hocalist.sale_pin_digits(uuid),hocalist.sale_keep_final(),hocalist.sale_pin(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.sale_pin(uuid,text,text) TO authenticated;
CREATE FUNCTION hocalist.sale_history(p_before_time timestamptz DEFAULT NULL,p_before_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();items jsonb;
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'sale_access_denied' USING ERRCODE='42501'; END IF;
 IF (p_before_time IS NULL)<>(p_before_id IS NULL) THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(x.data ORDER BY x.confirmed_at DESC,x.id DESC),'[]'::jsonb) INTO items FROM (
  SELECT s.id,s.confirmed_at,jsonb_build_object('id',s.id,'meeting_id',s.meeting_id,'confirmed_at',s.confirmed_at,
   'title',q.title,'price_minor',r.price_minor,'currency',r.currency_code) AS data
  FROM hocalist.sale_confirmations s JOIN hocalist.requests q ON q.id=s.request_id
  JOIN hocalist.offers o ON o.id=s.offer_id
  JOIN hocalist.offer_revisions r ON r.id=o.accepted_revision_id
  WHERE s.buyer_user_id=u AND (p_before_time IS NULL OR (s.confirmed_at,s.id)<(p_before_time,p_before_id))
  ORDER BY s.confirmed_at DESC,s.id DESC LIMIT 25
 ) x;
 RETURN jsonb_build_object('items',items);
END $$;
REVOKE ALL ON FUNCTION hocalist.sale_history(timestamptz,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.sale_history(timestamptz,uuid) TO authenticated;

-- Local accounting engine only. No client deposit/charge RPC, Stripe call,
-- paid activation, reward accrual or withdrawal execution is authorized here.

SET LOCAL lock_timeout='5s';
CREATE TABLE hocalist.credit_batches(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 deposit_reference text NOT NULL UNIQUE, original_minor bigint NOT NULL CHECK(original_minor>0),
 balance_minor bigint NOT NULL CHECK(balance_minor>=0), reserved_minor bigint NOT NULL DEFAULT 0 CHECK(reserved_minor>=0),
 initial_fee_minor bigint NOT NULL CHECK(initial_fee_minor>=0), winning_total_minor bigint NOT NULL,
 rate_version text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(winning_total_minor>=initial_fee_minor),CHECK(balance_minor>=reserved_minor)
);
CREATE TABLE hocalist.credit_targets(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 request_id uuid NOT NULL REFERENCES hocalist.requests(id), batch_id uuid NOT NULL REFERENCES hocalist.credit_batches(id),
 initial_minor bigint NOT NULL, winning_minor bigint NOT NULL,
 charged_minor bigint NOT NULL DEFAULT 0,reserved_minor bigint NOT NULL,
 status text NOT NULL DEFAULT 'reserved' CHECK(status IN ('reserved','initial_charged','won','released','refunded')),
 week_start date NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(user_id,request_id)
);
CREATE TABLE hocalist.credit_entries(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), batch_id uuid NOT NULL REFERENCES hocalist.credit_batches(id),
 target_id uuid REFERENCES hocalist.credit_targets(id), kind text NOT NULL,
 amount_minor bigint NOT NULL, reserve_delta_minor bigint NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.credit_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.credit_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.credit_entries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.credit_batches,hocalist.credit_targets,hocalist.credit_entries FROM PUBLIC,anon,authenticated,service_role;

-- Only the future approved server settlement path may call these helpers.
-- Deposit reference is a verified provider payment identity, never client text.
CREATE FUNCTION hocalist.credit_deposit_internal(p_user uuid,p_reference text,p_amount bigint,p_initial bigint,p_win bigint,p_rate text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b hocalist.credit_batches%ROWTYPE;
BEGIN
 IF p_user IS NULL OR p_reference IS NULL OR length(p_reference) NOT BETWEEN 1 AND 200 OR p_rate IS NULL OR length(p_rate) NOT BETWEEN 1 AND 100
  OR p_amount IS NULL OR p_amount<=0 OR p_initial IS NULL OR p_initial<0 OR p_win IS NULL OR p_win<p_initial OR p_win>p_amount THEN
  RAISE EXCEPTION 'invalid_deposit' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_reference,900));
 SELECT * INTO b FROM hocalist.credit_batches WHERE deposit_reference=p_reference;
 IF FOUND THEN
  IF b.user_id<>p_user OR b.original_minor<>p_amount OR b.initial_fee_minor<>p_initial OR b.winning_total_minor<>p_win OR b.rate_version<>p_rate THEN
   RAISE EXCEPTION 'idempotency_conflict'; END IF;
  RETURN b.id;
 END IF;
 INSERT INTO hocalist.credit_batches(user_id,deposit_reference,original_minor,balance_minor,initial_fee_minor,winning_total_minor,rate_version)
  VALUES(p_user,p_reference,p_amount,p_amount,p_initial,p_win,p_rate) RETURNING * INTO b;
 INSERT INTO hocalist.credit_entries(batch_id,kind,amount_minor,reserve_delta_minor) VALUES(b.id,'deposit',p_amount,0);
 RETURN b.id;
END $$;

CREATE FUNCTION hocalist.credit_reserve_internal(p_user uuid,p_request uuid,p_week date,p_limit integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b hocalist.credit_batches%ROWTYPE;t hocalist.credit_targets%ROWTYPE;
BEGIN
 IF p_week IS NULL OR p_limit IS NULL OR p_limit<1 THEN RAISE EXCEPTION 'invalid_quota' USING ERRCODE='22023'; END IF;
 -- Same seller lock across quota check, batch selection and all mutations.
 PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
 SELECT * INTO t FROM hocalist.credit_targets WHERE user_id=p_user AND request_id=p_request;
 IF FOUND THEN RETURN t.id; END IF;
 IF (SELECT count(*) FROM hocalist.credit_targets WHERE user_id=p_user AND week_start=p_week)>=p_limit THEN
  RAISE EXCEPTION 'weekly_target_limit'; END IF;
 SELECT * INTO b FROM hocalist.credit_batches WHERE user_id=p_user AND balance_minor-reserved_minor>=winning_total_minor
  ORDER BY created_at,id LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'insufficient_single_batch'; END IF;
 INSERT INTO hocalist.credit_targets(user_id,request_id,batch_id,initial_minor,winning_minor,reserved_minor,week_start)
  VALUES(p_user,p_request,b.id,b.initial_fee_minor,b.winning_total_minor,b.winning_total_minor,p_week) RETURNING * INTO t;
 UPDATE hocalist.credit_batches SET reserved_minor=reserved_minor+t.winning_minor WHERE id=b.id;
 INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(b.id,t.id,'reserve',0,t.winning_minor);
 RETURN t.id;
END $$;

CREATE FUNCTION hocalist.credit_settle_internal(p_target uuid,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t hocalist.credit_targets%ROWTYPE;charge bigint:=0;release bigint:=0;new_status text;
BEGIN
 SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target;
 IF NOT FOUND THEN RAISE EXCEPTION 'target_not_found' USING ERRCODE='P0002'; END IF;
 PERFORM 1 FROM hocalist.profiles WHERE id=t.user_id FOR UPDATE;
 SELECT * INTO t FROM hocalist.credit_targets WHERE id=p_target FOR UPDATE;
 IF p_action IS NULL OR p_action NOT IN ('initial','win','release','refund') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 IF (p_action='initial' AND t.status='initial_charged') OR (p_action='win' AND t.status='won')
  OR (p_action='release' AND t.status='released') OR (p_action='refund' AND t.status='refunded') THEN
  RETURN jsonb_build_object('id',t.id,'status',t.status,'charged_minor',t.charged_minor);
 END IF;
 IF t.status IN ('won','released','refunded') AND p_action<>'refund' THEN RAISE EXCEPTION 'target_final'; END IF;
 CASE p_action
  WHEN 'initial' THEN charge:=t.initial_minor-t.charged_minor;release:=charge;new_status:='initial_charged';
  WHEN 'win' THEN charge:=t.winning_minor-t.charged_minor;release:=t.reserved_minor;new_status:='won';
  WHEN 'release' THEN release:=t.reserved_minor;new_status:='released';
  WHEN 'refund' THEN charge:=-t.charged_minor;release:=t.reserved_minor;new_status:='refunded';
 END CASE;
 UPDATE hocalist.credit_batches SET balance_minor=balance_minor-charge,reserved_minor=reserved_minor-release WHERE id=t.batch_id;
 UPDATE hocalist.credit_targets SET charged_minor=charged_minor+charge,reserved_minor=reserved_minor-release,status=new_status WHERE id=t.id RETURNING * INTO t;
 INSERT INTO hocalist.credit_entries(batch_id,target_id,kind,amount_minor,reserve_delta_minor) VALUES(t.batch_id,t.id,p_action,-charge,-release);
 RETURN jsonb_build_object('id',t.id,'status',t.status,'charged_minor',t.charged_minor);
END $$;
CREATE FUNCTION hocalist.credit_wallet() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='seller' AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('currency','HC','balance_minor',coalesce((SELECT sum(balance_minor) FROM hocalist.credit_batches WHERE user_id=u),0),
  'reserved_minor',coalesce((SELECT sum(reserved_minor) FROM hocalist.credit_batches WHERE user_id=u),0),
  'batches',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'original_minor',original_minor,'balance_minor',balance_minor,
   'reserved_minor',reserved_minor,'initial_fee_minor',initial_fee_minor,'winning_total_minor',winning_total_minor,'rate_version',rate_version,'created_at',created_at) ORDER BY created_at,id)
   FROM hocalist.credit_batches WHERE user_id=u),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text),hocalist.credit_reserve_internal(uuid,uuid,date,integer),hocalist.credit_settle_internal(uuid,text),hocalist.credit_wallet() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.credit_wallet() TO authenticated;

-- Separate buyer reward ledger. No payout execution or automatic accrual.

CREATE TABLE hocalist.buyer_rewards (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 outcome_id uuid NOT NULL UNIQUE REFERENCES hocalist.sale_confirmations(id),
 target_id uuid NOT NULL UNIQUE REFERENCES hocalist.credit_targets(id),
 buyer_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),
 rule_version text NOT NULL CHECK(length(rule_version) BETWEEN 1 AND 100),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.buyer_rewards ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.buyer_rewards FROM PUBLIC,anon,authenticated,service_role;
-- Only a subsequently approved settlement path may execute this helper.
-- Rates and late-window qualification are deliberately not inferred here.
CREATE FUNCTION hocalist.reward_accrue_internal(p_outcome uuid,p_target uuid,p_amount bigint,p_rule text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE outcome hocalist.sale_confirmations%ROWTYPE;target hocalist.credit_targets%ROWTYPE;reward hocalist.buyer_rewards%ROWTYPE;
BEGIN
 IF p_amount IS NULL OR p_amount<=0 OR p_rule IS NULL OR length(btrim(p_rule)) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_reward'; END IF;
 SELECT * INTO STRICT outcome FROM hocalist.sale_confirmations WHERE id=p_outcome;
 -- Same lock as credit settlement: never accrue concurrently with a refund.
 PERFORM 1 FROM hocalist.profiles WHERE id=outcome.seller_user_id FOR UPDATE;
 SELECT * INTO target FROM hocalist.credit_targets WHERE id=p_target;
 IF NOT FOUND OR target.request_id<>outcome.request_id OR target.user_id<>outcome.seller_user_id
  OR target.status<>'won' OR target.charged_minor<>target.winning_minor OR target.charged_minor<=0 THEN
  RAISE EXCEPTION 'collected_sale_fee_required'; END IF;
 SELECT * INTO reward FROM hocalist.buyer_rewards WHERE outcome_id=p_outcome;
 IF FOUND THEN
  IF reward.target_id<>p_target OR reward.amount_minor<>p_amount OR reward.rule_version<>p_rule THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
  RETURN reward.id;
 END IF;
 INSERT INTO hocalist.buyer_rewards(outcome_id,target_id,buyer_user_id,amount_minor,rule_version)
 VALUES(p_outcome,p_target,outcome.buyer_user_id,p_amount,p_rule) RETURNING * INTO reward;
 RETURN reward.id;
END $$;
CREATE FUNCTION hocalist.reward_wallet() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();
BEGIN
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND role='buyer' AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'wallet_access_denied' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('currency','USD','withdrawals_enabled',false,
  'earned_minor',coalesce((SELECT sum(r.amount_minor) FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id WHERE r.buyer_user_id=u AND t.status='won'),0),
  'items',coalesce((SELECT jsonb_agg(x.data ORDER BY x.created_at DESC,x.id DESC) FROM (
   SELECT r.id,r.created_at,jsonb_build_object('id',r.id,'amount_minor',r.amount_minor,'created_at',r.created_at,
    'status',CASE WHEN t.status='won' THEN 'earned' ELSE 'held' END) AS data
   FROM hocalist.buyer_rewards r JOIN hocalist.credit_targets t ON t.id=r.target_id
   WHERE r.buyer_user_id=u ORDER BY r.created_at DESC,r.id DESC LIMIT 50) x),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION hocalist.reward_accrue_internal(uuid,uuid,bigint,text),hocalist.reward_wallet() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.reward_wallet() TO authenticated;

-- Private image metadata. Bytes are accepted only through the authenticated,
-- bounded image gateway and re-encoded before entering the private bucket.

CREATE TABLE hocalist.media_images(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 intent_key uuid NOT NULL, purpose text NOT NULL CHECK(purpose IN ('offer','store','profile','chat')),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','ready','rejected')),
 size_bytes integer CHECK(size_bytes BETWEEN 1 AND 4194304),
 width integer CHECK(width BETWEEN 1 AND 2048),height integer CHECK(height BETWEEN 1 AND 2048),
 content_hash text NOT NULL CHECK(content_hash~'^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(owner_user_id,intent_key)
);
ALTER TABLE hocalist.media_images ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.media_images FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE hocalist.media_windows(user_id uuid PRIMARY KEY REFERENCES hocalist.profiles(id),started_at timestamptz NOT NULL,calls integer NOT NULL);
ALTER TABLE hocalist.media_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.media_windows FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.media_gateway(p_user uuid,p_action text,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m hocalist.media_images%ROWTYPE; image_id uuid;purpose text;n integer;
BEGIN
 IF p_user IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND status IN ('restricted','disabled')) THEN
  RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501'; END IF;
 INSERT INTO hocalist.media_windows(user_id,started_at,calls) VALUES(p_user,now(),1)
 ON CONFLICT(user_id) DO UPDATE SET
  calls=CASE WHEN media_windows.started_at<now()-interval '1 minute' THEN 1 ELSE media_windows.calls+1 END,
  started_at=CASE WHEN media_windows.started_at<now()-interval '1 minute' THEN now() ELSE media_windows.started_at END RETURNING calls INTO n;
 IF n>60 THEN RAISE EXCEPTION 'media_rate_limit'; END IF;
 IF p_action='begin' THEN
  purpose:=p_input->>'purpose';
  IF purpose IN ('offer','store') AND NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=p_user AND role='seller' AND status='active') THEN
   RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  SELECT * INTO m FROM hocalist.media_images WHERE owner_user_id=p_user AND intent_key=(p_input->>'key')::uuid;
  IF FOUND THEN
   IF m.purpose<>purpose OR m.content_hash<>p_input->>'hash' THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
  ELSE
   IF (SELECT count(*) FROM hocalist.media_images WHERE owner_user_id=p_user AND created_at>now()-interval '1 hour')>=60 THEN RAISE EXCEPTION 'media_rate_limit'; END IF;
   INSERT INTO hocalist.media_images(owner_user_id,intent_key,purpose,content_hash)
    VALUES(p_user,(p_input->>'key')::uuid,purpose,p_input->>'hash') RETURNING * INTO m;
  END IF;
 ELSIF p_action='complete' THEN
  UPDATE hocalist.media_images SET state='ready',size_bytes=(p_input->>'size')::integer,width=(p_input->>'width')::integer,height=(p_input->>'height')::integer
   WHERE id=(p_input->>'id')::uuid AND owner_user_id=p_user AND state IN ('pending','ready') RETURNING * INTO m;
  IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
 ELSIF p_action='read' THEN
  image_id:=(p_input->>'id')::uuid;
  SELECT * INTO m FROM hocalist.media_images WHERE id=image_id AND state='ready';
  IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='P0002'; END IF;
  IF m.owner_user_id<>p_user AND NOT (
   (m.purpose='store' AND EXISTS(SELECT 1 FROM hocalist.store_listings l JOIN hocalist.memberships s ON s.id=l.seller_profile_id
    WHERE l.image_media_ids ? image_id::text AND l.status='active' AND l.moderation_status='approved' AND s.status='active'))
   OR (m.purpose='offer' AND EXISTS(SELECT 1 FROM hocalist.offer_revisions r JOIN hocalist.offers o ON o.id=r.offer_id
    JOIN hocalist.requests q ON q.id=o.request_id WHERE r.image_media_ids ? image_id::text AND q.buyer_user_id=p_user))
  ) THEN RAISE EXCEPTION 'media_access_denied' USING ERRCODE='42501'; END IF;
 ELSE RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('id',m.id,'path',m.owner_user_id::text||'/'||m.id::text||'.jpg','state',m.state);
END $$;
-- References must be real, ready, owned assets of the appropriate purpose.
CREATE FUNCTION hocalist.media_validate_references() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE owner_id uuid; v_purpose text; item text;
BEGIN
 IF TG_TABLE_NAME='store_listings' THEN
  SELECT user_id INTO owner_id FROM hocalist.memberships WHERE id=NEW.seller_profile_id;v_purpose:='store';
 ELSE
  SELECT seller_user_id INTO owner_id FROM hocalist.offers WHERE id=NEW.offer_id;v_purpose:='offer';
 END IF;
 FOR item IN SELECT jsonb_array_elements_text(NEW.image_media_ids) LOOP
  IF NOT EXISTS(SELECT 1 FROM hocalist.media_images WHERE id=item::uuid AND owner_user_id=owner_id AND state='ready' AND media_images.purpose=v_purpose) THEN
   RAISE EXCEPTION 'invalid_media_reference' USING ERRCODE='22023'; END IF;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_store_media BEFORE INSERT OR UPDATE OF image_media_ids ON hocalist.store_listings FOR EACH ROW EXECUTE FUNCTION hocalist.media_validate_references();
CREATE TRIGGER validate_offer_media BEFORE INSERT ON hocalist.offer_revisions FOR EACH ROW EXECUTE FUNCTION hocalist.media_validate_references();
REVOKE ALL ON FUNCTION hocalist.media_gateway(uuid,text,jsonb),hocalist.media_validate_references() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.media_gateway(uuid,text,jsonb) TO service_role;

-- Hocalist-owned, two-person WebRTC signaling. Media never enters this DB.

CREATE TABLE hocalist.calls(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id),
 caller_id uuid NOT NULL REFERENCES hocalist.profiles(id),callee_id uuid NOT NULL REFERENCES hocalist.profiles(id),
 intent_key uuid NOT NULL,state text NOT NULL DEFAULT 'ringing' CHECK(state IN ('ringing','accepted','declined','cancelled','ended','missed')),
 created_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL DEFAULT now()+interval '45 seconds',
 caller_seen_at timestamptz NOT NULL DEFAULT now(),callee_seen_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(caller_id,intent_key),CHECK(caller_id<>callee_id)
);
CREATE TABLE hocalist.call_signals(
 seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,call_id uuid NOT NULL REFERENCES hocalist.calls(id) ON DELETE CASCADE,
 sender_id uuid NOT NULL,intent_key uuid NOT NULL,kind text NOT NULL CHECK(kind IN ('offer','answer','candidate')),
 payload jsonb NOT NULL CHECK(octet_length(payload::text)<=65536),UNIQUE(call_id,sender_id,intent_key)
);
ALTER TABLE hocalist.calls ENABLE ROW LEVEL SECURITY;ALTER TABLE hocalist.call_signals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.calls,hocalist.call_signals FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE hocalist.call_signals_seq_seq FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE hocalist.call_settings (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 enabled boolean NOT NULL DEFAULT false, revision bigint NOT NULL DEFAULT 1,
 changed_by uuid, changed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.call_settings DEFAULT VALUES;
CREATE TABLE hocalist.call_settings_audit (
 revision bigint PRIMARY KEY, enabled boolean NOT NULL, changed_by uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hocalist.call_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.call_settings_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.call_settings,hocalist.call_settings_audit FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hocalist.call_admin_settings(p_enabled boolean DEFAULT NULL,p_revision bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s hocalist.call_settings%ROWTYPE;
BEGIN
 PERFORM hocalist.marketplace_assert_admin(auth.uid());
 PERFORM pg_advisory_xact_lock(110,1);
 SELECT * INTO STRICT s FROM hocalist.call_settings WHERE singleton FOR UPDATE;
 IF p_enabled IS NOT NULL THEN
  IF p_revision IS DISTINCT FROM s.revision THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='40001'; END IF;
  IF s.enabled IS DISTINCT FROM p_enabled THEN
   UPDATE hocalist.call_settings SET enabled=p_enabled,revision=revision+1,changed_by=auth.uid(),changed_at=now()
    WHERE singleton RETURNING * INTO s;
   INSERT INTO hocalist.call_settings_audit(revision,enabled,changed_by) VALUES(s.revision,s.enabled,auth.uid());
   IF NOT s.enabled THEN
    UPDATE hocalist.calls SET state='ended' WHERE state IN ('ringing','accepted');
    DELETE FROM hocalist.call_signals;
   END IF;
  END IF;
 END IF;
 RETURN jsonb_build_object('enabled',s.enabled,'revision',s.revision);
END $$;
REVOKE ALL ON FUNCTION hocalist.call_admin_settings(boolean,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.call_admin_settings(boolean,bigint) TO authenticated;
CREATE FUNCTION hocalist.call_command(p_action text,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();c hocalist.calls%ROWTYPE;peer uuid;conv uuid;item hocalist.call_signals%ROWTYPE;items jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'unauthorized' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_input)<>'object' OR octet_length(p_input::text)>70000 THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status='active')
  OR EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501'; END IF;
 -- Serialize the small MVP control plane across invitations, busy checks and
 -- terminal cleanup. Revisit partitioning only with measured call volume.
 PERFORM pg_advisory_xact_lock(110,1);
 UPDATE hocalist.calls SET state=CASE WHEN state='ringing' THEN 'missed' ELSE 'ended' END
  WHERE state IN ('ringing','accepted') AND expires_at<=now();
 DELETE FROM hocalist.call_signals s USING hocalist.calls d WHERE s.call_id=d.id AND d.state NOT IN ('ringing','accepted');
 IF NOT coalesce((SELECT enabled FROM hocalist.call_settings WHERE singleton),false) THEN
  IF p_action='incoming' THEN RETURN jsonb_build_object('call',NULL,'enabled',false); END IF;
  IF p_action NOT IN ('poll','end') THEN RAISE EXCEPTION 'calls_disabled' USING ERRCODE='42501'; END IF;
 END IF;
 IF p_action='incoming' THEN
  SELECT * INTO c FROM hocalist.calls WHERE callee_id=u AND state='ringing' ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('call',NULL); END IF;
 ELSE
  IF p_action='invite' THEN
   conv:=(p_input->>'conversation_id')::uuid;
   PERFORM hocalist.chat_assert_participant(conv,u);
   IF NOT EXISTS(SELECT 1 FROM hocalist.meetings WHERE conversation_id=conv AND status='accepted') THEN RAISE EXCEPTION 'meeting_required'; END IF;
   SELECT user_id INTO peer FROM hocalist.conversation_members WHERE conversation_id=conv AND user_id<>u AND revoked_at IS NULL;
   PERFORM hocalist.chat_assert_participant(conv,peer);
   SELECT * INTO c FROM hocalist.calls WHERE caller_id=u AND intent_key=(p_input->>'key')::uuid;
   IF FOUND THEN
    IF c.conversation_id<>conv THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
   ELSE
    IF EXISTS(SELECT 1 FROM hocalist.calls WHERE state IN ('ringing','accepted') AND (caller_id IN (u,peer) OR callee_id IN (u,peer))) THEN
     RETURN jsonb_build_object('status','busy'); END IF;
    IF (SELECT count(*) FROM hocalist.calls WHERE caller_id=u AND created_at>now()-interval '1 hour')>=20 THEN RAISE EXCEPTION 'call_rate_limit'; END IF;
    INSERT INTO hocalist.calls(conversation_id,caller_id,callee_id,intent_key) VALUES(conv,u,peer,(p_input->>'key')::uuid) RETURNING * INTO c;
   END IF;
  ELSE
   SELECT * INTO c FROM hocalist.calls WHERE id=(p_input->>'call_id')::uuid;
   IF NOT FOUND THEN RAISE EXCEPTION 'call_not_found' USING ERRCODE='P0002'; END IF;
  END IF;
 END IF;
 IF u NOT IN (c.caller_id,c.callee_id) THEN RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501'; END IF;
 PERFORM hocalist.chat_assert_participant(c.conversation_id,u);
 IF NOT EXISTS(SELECT 1 FROM hocalist.conversations WHERE id=c.conversation_id AND status='open') THEN RAISE EXCEPTION 'conversation_closed'; END IF;
 -- Revocation on either side ends eligibility to exchange signaling.
 PERFORM hocalist.chat_assert_participant(c.conversation_id,CASE WHEN u=c.caller_id THEN c.callee_id ELSE c.caller_id END);
 IF p_action IN ('accept','decline') THEN
  IF u<>c.callee_id THEN RAISE EXCEPTION 'call_access_denied' USING ERRCODE='42501'; END IF;
  IF c.state='ringing' THEN
   UPDATE hocalist.calls SET state=CASE p_action WHEN 'accept' THEN 'accepted' ELSE 'declined' END,
    expires_at=now()+interval '90 seconds',caller_seen_at=now(),callee_seen_at=now() WHERE id=c.id RETURNING * INTO c;
  ELSIF NOT ((p_action='accept' AND c.state='accepted') OR (p_action='decline' AND c.state='declined')) THEN RAISE EXCEPTION 'call_finished'; END IF;
 ELSIF p_action='end' THEN
  UPDATE hocalist.calls SET state=CASE WHEN state='ringing' THEN 'cancelled' ELSE 'ended' END WHERE id=c.id AND state IN ('ringing','accepted') RETURNING * INTO c;
  IF NOT FOUND THEN SELECT * INTO c FROM hocalist.calls WHERE id=(p_input->>'call_id')::uuid; END IF;
 ELSIF p_action='signal' THEN
  IF c.state<>'accepted' THEN RAISE EXCEPTION 'call_not_accepted'; END IF;
  IF (p_input->>'kind'='offer' AND u<>c.caller_id) OR (p_input->>'kind'='answer' AND u<>c.callee_id) THEN RAISE EXCEPTION 'invalid_signal_role'; END IF;
  SELECT * INTO item FROM hocalist.call_signals WHERE call_id=c.id AND sender_id=u AND intent_key=(p_input->>'key')::uuid;
  IF FOUND THEN
   IF item.kind<>p_input->>'kind' OR item.payload IS DISTINCT FROM p_input->'payload' THEN RAISE EXCEPTION 'idempotency_conflict'; END IF;
  ELSE
   IF (SELECT count(*) FROM hocalist.call_signals WHERE call_id=c.id AND sender_id=u)>=256 THEN RAISE EXCEPTION 'signal_limit'; END IF;
   INSERT INTO hocalist.call_signals(call_id,sender_id,intent_key,kind,payload) VALUES(c.id,u,(p_input->>'key')::uuid,p_input->>'kind',p_input->'payload');
  END IF;
 ELSIF p_action NOT IN ('invite','incoming','poll') OR p_action IS NULL THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';
 END IF;
 IF p_action='poll' AND c.state='accepted' THEN
  UPDATE hocalist.calls SET caller_seen_at=CASE WHEN caller_id=u THEN now() ELSE caller_seen_at END,
   callee_seen_at=CASE WHEN callee_id=u THEN now() ELSE callee_seen_at END WHERE id=c.id RETURNING * INTO c;
  UPDATE hocalist.calls SET expires_at=least(c.caller_seen_at,c.callee_seen_at)+interval '90 seconds' WHERE id=c.id;
 END IF;
 IF c.state NOT IN ('ringing','accepted') THEN DELETE FROM hocalist.call_signals WHERE call_id=c.id; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('seq',s.seq,'kind',s.kind,'payload',s.payload) ORDER BY s.seq),'[]'::jsonb) INTO items
  FROM hocalist.call_signals s WHERE s.call_id=c.id AND s.sender_id<>u AND s.seq>coalesce((p_input->>'cursor')::bigint,0);
 RETURN jsonb_build_object('call',jsonb_build_object('id',c.id,'conversation_id',c.conversation_id,'caller_id',c.caller_id,'callee_id',c.callee_id,'state',c.state),'signals',items);
END $$;
REVOKE ALL ON FUNCTION hocalist.call_command(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.call_command(text,jsonb) TO authenticated;

DO $verify$ DECLARE t text;r text;priv text;f oid; BEGIN
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.buyer_rewards')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: buyer_rewards'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.buyer_rewards',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: buyer_rewards % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.buyer_rewards','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: buyer_rewards'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.buyer_rewards'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: buyer_rewards'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.buyer_rewards'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: buyer_rewards'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.buyer_rewards'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: buyer_rewards'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.call_settings')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: call_settings'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.call_settings',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: call_settings % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.call_settings','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: call_settings'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.call_settings'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: call_settings'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.call_settings'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: call_settings'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.call_settings'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: call_settings'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.call_settings_audit')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: call_settings_audit'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.call_settings_audit',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: call_settings_audit % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.call_settings_audit','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: call_settings_audit'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.call_settings_audit'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: call_settings_audit'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.call_settings_audit'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: call_settings_audit'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.call_settings_audit'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: call_settings_audit'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.call_signals')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: call_signals'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.call_signals',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: call_signals % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.call_signals','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: call_signals'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.call_signals'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: call_signals'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.call_signals'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: call_signals'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.call_signals'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: call_signals'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.calls')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: calls'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.calls',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: calls % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.calls','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: calls'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.calls'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: calls'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.calls'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: calls'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.calls'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: calls'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.credit_batches')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: credit_batches'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.credit_batches',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: credit_batches % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.credit_batches','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: credit_batches'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.credit_batches'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: credit_batches'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.credit_batches'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: credit_batches'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.credit_batches'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: credit_batches'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.credit_entries')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: credit_entries'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.credit_entries',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: credit_entries % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.credit_entries','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: credit_entries'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.credit_entries'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: credit_entries'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.credit_entries'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: credit_entries'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.credit_entries'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: credit_entries'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.credit_targets')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: credit_targets'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.credit_targets',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: credit_targets % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.credit_targets','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: credit_targets'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.credit_targets'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: credit_targets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.credit_targets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: credit_targets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.credit_targets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: credit_targets'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.media_images')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: media_images'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.media_images',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: media_images % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.media_images','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: media_images'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.media_images'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: media_images'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.media_images'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: media_images'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.media_images'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: media_images'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.media_windows')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: media_windows'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.media_windows',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: media_windows % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.media_windows','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: media_windows'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.media_windows'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: media_windows'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.media_windows'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: media_windows'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.media_windows'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: media_windows'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.request_pin_secrets')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: request_pin_secrets'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.request_pin_secrets',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: request_pin_secrets % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.request_pin_secrets','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: request_pin_secrets'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.request_pin_secrets'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: request_pin_secrets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.request_pin_secrets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: request_pin_secrets'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.request_pin_secrets'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: request_pin_secrets'; END IF;
IF NOT coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('hocalist.sale_confirmations')),false) THEN RAISE EXCEPTION 'Missing private table/RLS: sale_confirmations'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  FOREACH priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'hocalist.sale_confirmations',priv) THEN RAISE EXCEPTION 'Unexpected table privilege: sale_confirmations % %',r,priv; END IF;
  END LOOP;
  IF has_any_column_privilege(r,'hocalist.sale_confirmations','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected column privilege: sale_confirmations'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='hocalist.sale_confirmations'::regclass) THEN RAISE EXCEPTION 'Unexpected table policy: sale_confirmations'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid='hocalist.sale_confirmations'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct table ACL: sale_confirmations'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute col JOIN pg_class c ON c.oid=col.attrelid,LATERAL aclexplode(col.attacl) a WHERE c.oid='hocalist.sale_confirmations'::regclass AND a.grantee<>c.relowner) THEN RAISE EXCEPTION 'Unexpected direct column ACL: sale_confirmations'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.meetings'::regclass AND tgname='sale_final_meeting' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='0537d9a7bb9fc605613148ba40f35a06') THEN RAISE EXCEPTION 'Trigger drift: sale_final_meeting'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.offer_revisions'::regclass AND tgname='validate_offer_media' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='3fec917dfa1a63b625859697b98d489e') THEN RAISE EXCEPTION 'Trigger drift: validate_offer_media'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.requests'::regclass AND tgname='sale_final_request' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='35400bfb091ab614106faa2badcd90ef') THEN RAISE EXCEPTION 'Trigger drift: sale_final_request'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.store_listings'::regclass AND tgname='validate_store_media' AND tgenabled='O' AND md5(pg_get_triggerdef(oid))='1962604f4ed74b54c33d880b3f7dbb13') THEN RAISE EXCEPTION 'Trigger drift: validate_store_media'; END IF;
f:=to_regprocedure('hocalist.call_admin_settings(boolean,bigint)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'1513de4bb8410c05e2acf35915a38aa3' THEN RAISE EXCEPTION 'Function drift: hocalist.call_admin_settings(boolean,bigint)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.call_admin_settings(boolean,bigint)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.call_admin_settings(boolean,bigint) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.call_command(text,jsonb)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'49221a424fc1c80032f56da8a71de9bd' THEN RAISE EXCEPTION 'Function drift: hocalist.call_command(text,jsonb)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.call_command(text,jsonb)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.call_command(text,jsonb) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'55a81f0fc32a0f491cfb961d0da425d9' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_deposit_internal(uuid,text,bigint,bigint,bigint,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_reserve_internal(uuid,uuid,date,integer)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'e421ff54b6828e30ec09c309dd56d637' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_reserve_internal(uuid,uuid,date,integer)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_reserve_internal(uuid,uuid,date,integer)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_reserve_internal(uuid,uuid,date,integer) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_settle_internal(uuid,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'90b8852109c1c612f7a5cc94ab389bd2' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_settle_internal(uuid,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_settle_internal(uuid,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_settle_internal(uuid,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.credit_wallet()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'ade39ebd47e0ebf915a901e4e587b2e4' THEN RAISE EXCEPTION 'Function drift: hocalist.credit_wallet()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.credit_wallet()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.credit_wallet() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'b88abb275cc2fd083efcfb7f407c3488' THEN RAISE EXCEPTION 'Function drift: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['service_role']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.media_gateway(uuid,text,jsonb)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['service_role']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.media_gateway(uuid,text,jsonb) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.media_validate_references()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'5b74ed0d1f3b4a54022f00a1e468e1a1' THEN RAISE EXCEPTION 'Function drift: hocalist.media_validate_references()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.media_validate_references()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.media_validate_references() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.reward_accrue_internal(uuid,uuid,bigint,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'406401847ece809b5b1430f3e412aed8' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_accrue_internal(uuid,uuid,bigint,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.reward_accrue_internal(uuid,uuid,bigint,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.reward_accrue_internal(uuid,uuid,bigint,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.reward_wallet()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'bd5248bf235b034fcdeed1d5d5a0113c' THEN RAISE EXCEPTION 'Function drift: hocalist.reward_wallet()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.reward_wallet()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.reward_wallet() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_history(timestamp with time zone,uuid)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'4dc9bccc3ae24ee859b891919fb78c8b' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_history(timestamp with time zone,uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_history(timestamp with time zone,uuid)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_history(timestamp with time zone,uuid) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_keep_final()');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c7d38610c3a485095b71ad79aeeb94db' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_keep_final()'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_keep_final()'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_keep_final() %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_pin(uuid,text,text)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'c935b662860d575095ba45ed6daaf5c5' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_pin(uuid,text,text)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY['authenticated']::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_pin(uuid,text,text)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY['authenticated']::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_pin(uuid,text,text) %',r; END IF;
 END LOOP;
f:=to_regprocedure('hocalist.sale_pin_digits(uuid)');
 IF f IS NULL OR md5(replace(pg_get_functiondef(f),chr(13),''))<>'52d6a0f0c08573903e0a1275a61358e6' THEN RAISE EXCEPTION 'Function drift: hocalist.sale_pin_digits(uuid)'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=f AND a.grantee<>p.proowner AND (a.grantee=0 OR a.is_grantable OR NOT a.grantee=ANY(ARRAY(SELECT oid FROM pg_roles WHERE rolname=ANY(ARRAY[]::text[]))))) THEN RAISE EXCEPTION 'Unexpected function ACL: hocalist.sale_pin_digits(uuid)'; END IF;
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  IF has_function_privilege(r,f,'EXECUTE') IS DISTINCT FROM (r=ANY(ARRAY[]::text[])) THEN RAISE EXCEPTION 'Function privilege drift: hocalist.sale_pin_digits(uuid) %',r; END IF;
 END LOOP;
 IF (SELECT enabled FROM hocalist.call_settings WHERE singleton) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Calls must remain off during rollout'; END IF;
END $verify$;
COMMIT;

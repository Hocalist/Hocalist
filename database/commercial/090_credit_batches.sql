-- Local accounting engine only. No client deposit/charge RPC, Stripe call,
-- paid activation, reward accrual or withdrawal execution is authorized here.
BEGIN;
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
COMMIT;

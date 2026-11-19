-- Stripe customers and sessions are account-specific. Preserve historical
-- customer, subscription and credit-batch bindings across the sandbox cutover.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE hocalist.stripe_test_checkouts
  ADD COLUMN IF NOT EXISTS qa_credit boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS qa_customer text,
  ADD COLUMN IF NOT EXISTS qa_checked_at timestamptz;

CREATE OR REPLACE FUNCTION hocalist.qa_credit_begin(p_user uuid,p_key uuid,p_option uuid DEFAULT NULL,p_amount bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; old_id uuid; c hocalist.stripe_test_checkouts%ROWTYPE;
BEGIN
  PERFORM 1 FROM hocalist.profiles WHERE id=p_user FOR UPDATE;
  SELECT s.id INTO old_id FROM hocalist.stripe_test_checkouts s JOIN hocalist.memberships m ON m.id=s.membership_id
    WHERE m.user_id=p_user AND m.role='seller' AND s.request_key=p_key;
  IF (p_option IS NULL)=(p_amount IS NULL) THEN RAISE EXCEPTION 'invalid_option_or_key'; END IF;
  IF p_option IS NULL THEN result:=hocalist.stripe_test_standard_deposit_begin(p_user,p_amount,p_key);
  ELSE result:=hocalist.stripe_test_deposit_begin(p_user,p_option,p_key); END IF;
  IF old_id IS NULL THEN
    UPDATE hocalist.stripe_test_checkouts SET qa_credit=true WHERE id=(result->>'checkout_id')::uuid;
  END IF;
  SELECT * INTO STRICT c FROM hocalist.stripe_test_checkouts WHERE id=(result->>'checkout_id')::uuid;
  IF c.qa_credit THEN RETURN result || jsonb_build_object('qa_credit',true,'customer_id',c.qa_customer); END IF;
  RETURN result;
END $$;

DO $patch$
DECLARE d text; a text;
BEGIN
  SELECT pg_get_functiondef('hocalist.stripe_test_deposit_bind(uuid,text,text,text)'::regprocedure) INTO d;
  IF strpos(d,'c.qa_credit')=0 THEN
    a:='INSERT INTO hocalist.stripe_test_customers';
    IF strpos(d,a)=0 OR strpos(d,'IF p_session IS NOT NULL THEN')=0 THEN RAISE EXCEPTION 'bind drift'; END IF;
    EXECUTE replace(replace(d,a,'IF c.qa_credit THEN
      IF c.qa_customer IS NOT NULL AND c.qa_customer<>p_customer THEN RAISE EXCEPTION ''customer_conflict''; END IF;
      UPDATE hocalist.stripe_test_checkouts SET qa_customer=p_customer WHERE id=c.id;
      ELSE '||a),'IF p_session IS NOT NULL THEN','END IF; IF p_session IS NOT NULL THEN');
  END IF;
  SELECT pg_get_functiondef('hocalist.stripe_test_deposit_finish(uuid,text,bigint,text,text)'::regprocedure) INTO d;
  IF strpos(d,'c.qa_credit')=0 THEN
    a:='IF p_customer IS NULL OR NOT EXISTS(';
    IF strpos(d,a)=0 OR strpos(d,'customer_id=p_customer) THEN')=0 THEN RAISE EXCEPTION 'finish drift'; END IF;
    d:=replace(replace(d,a,'IF p_customer IS NULL OR (CASE WHEN c.qa_credit THEN c.qa_customer IS DISTINCT FROM p_customer ELSE NOT EXISTS('),
      'customer_id=p_customer) THEN','customer_id=p_customer) END) THEN');
    d:=replace(d,'SET requires_review=true WHERE membership_id=c.membership_id','SET requires_review=true WHERE NOT c.qa_credit AND membership_id=c.membership_id');
    EXECUTE d;
  END IF;
  SELECT pg_get_functiondef('hocalist.stripe_test_pending_checkout(uuid)'::regprocedure) INTO d;
  IF strpos(d,'c.qa_credit')=0 THEN
    a:='''customer_id'',sc.customer_id';
    IF strpos(d,a)=0 THEN RAISE EXCEPTION 'pending drift'; END IF;
    EXECUTE replace(d,a,'''qa_credit'',c.qa_credit,''customer_id'',CASE WHEN c.qa_credit THEN c.qa_customer ELSE sc.customer_id END');
  END IF;
  SELECT pg_get_functiondef('hocalist.stripe_test_checkout_expire(uuid,text,text)'::regprocedure) INTO d;
  IF strpos(d,'c.qa_credit')=0 THEN
    a:='AND EXISTS(SELECT 1 FROM hocalist.stripe_test_customers x WHERE x.membership_id=c.membership_id AND x.customer_id=p_customer)';
    IF strpos(d,a)=0 THEN RAISE EXCEPTION 'expire drift'; END IF;
    EXECUTE replace(d,a,'AND CASE WHEN c.qa_credit THEN c.qa_customer=p_customer ELSE '||substr(a,5)||' END');
  END IF;
END $patch$;

CREATE OR REPLACE FUNCTION hocalist.qa_credit_pending_sessions()
RETURNS SETOF jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  WITH due AS (SELECT id FROM hocalist.stripe_test_checkouts WHERE qa_credit AND state='open'
    AND session_id IS NOT NULL AND (qa_checked_at IS NULL OR qa_checked_at<now()-interval '30 seconds')
    ORDER BY qa_checked_at NULLS FIRST,created_at LIMIT 12 FOR UPDATE SKIP LOCKED)
  UPDATE hocalist.stripe_test_checkouts c SET qa_checked_at=now() FROM due WHERE c.id=due.id
  RETURNING jsonb_build_object('id',c.id,'session_id',c.session_id,'customer_id',c.qa_customer,
    'membership_id',c.membership_id,'amount_minor',c.amount_minor,'kind',c.kind)
$$;
REVOKE ALL ON FUNCTION hocalist.qa_credit_begin(uuid,uuid,uuid,bigint),hocalist.qa_credit_pending_sessions() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.qa_credit_begin(uuid,uuid,uuid,bigint),hocalist.qa_credit_pending_sessions() TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

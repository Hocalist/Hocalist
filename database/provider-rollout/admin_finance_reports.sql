BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE TABLE hocalist.admin_finance_month_entries (
  month date NOT NULL CHECK (extract(day FROM month) = 1),
  revision integer NOT NULL CHECK (revision > 0),
  totals jsonb NOT NULL,
  note text NOT NULL CHECK (char_length(note) BETWEEN 1 AND 240),
  entered_by uuid NOT NULL,
  entered_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (month, revision)
);
ALTER TABLE hocalist.admin_finance_month_entries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.admin_finance_month_entries FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE hocalist.admin_finance_stripe_invoices (
  account_id text NOT NULL CHECK (left(account_id, 5) = 'acct_'),
  invoice_id text NOT NULL CHECK (left(invoice_id, 3) = 'in_'),
  paid_month date NOT NULL CHECK (extract(day FROM paid_month) = 1),
  customer_revenue_minor bigint NOT NULL CHECK (customer_revenue_minor >= 0),
  reconciled_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, invoice_id)
);
ALTER TABLE hocalist.admin_finance_stripe_invoices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.admin_finance_stripe_invoices FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION hocalist.admin_finance_assert_access()
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  IF coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN
    RAISE EXCEPTION 'admin_mfa_required' USING ERRCODE='42501';
  END IF;
END;
$$;

CREATE FUNCTION hocalist.admin_finance_save_month(
  p_month date, p_revision integer, p_totals jsonb, p_note text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  current_month date := date_trunc('month', now() AT TIME ZONE 'America/New_York')::date;
  current_revision integer;
  allowed text[] := ARRAY['subscriptions','targeting','confirmation','stripeFees','refunds','rewardsEarned','overhead'];
BEGIN
  PERFORM hocalist.admin_finance_assert_access();
  IF p_month IS NULL OR extract(day FROM p_month) <> 1 OR
     p_month < (current_month - interval '5 months')::date OR p_month > current_month OR
     p_revision IS NULL OR p_revision < 0 OR
     p_note IS NULL OR char_length(btrim(p_note)) NOT BETWEEN 1 AND 240 OR
     coalesce(jsonb_typeof(p_totals), '') <> 'object' OR NOT p_totals ?& allowed THEN
    RAISE EXCEPTION 'invalid_finance_month' USING ERRCODE='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_each(p_totals) AS entry(key, value)
    WHERE NOT (key = ANY(allowed))
       OR (value <> 'null'::jsonb AND (
         jsonb_typeof(value) <> 'number' OR value::text !~ '^[0-9]{1,10}$'
       ))
  ) THEN
    RAISE EXCEPTION 'invalid_finance_totals' USING ERRCODE='22023';
  END IF;
  IF p_totals->'subscriptions' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'finance_subscriptions_require_stripe' USING ERRCODE='22023';
  END IF;

  PERFORM pg_advisory_xact_lock(439924, p_month - date '2000-01-01');
  SELECT coalesce(max(revision), 0) INTO current_revision
  FROM hocalist.admin_finance_month_entries WHERE month = p_month;
  IF current_revision <> p_revision THEN
    RAISE EXCEPTION 'finance_month_changed' USING ERRCODE='40001';
  END IF;
  INSERT INTO hocalist.admin_finance_month_entries(month, revision, totals, note, entered_by)
  VALUES (p_month, current_revision + 1, p_totals, btrim(p_note), auth.uid());
  RETURN jsonb_build_object('revision', current_revision + 1);
END;
$$;

CREATE FUNCTION hocalist.admin_finance_overview()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  result jsonb;
BEGIN
  PERFORM hocalist.admin_finance_assert_access();
  WITH bounds AS (
    SELECT date_trunc('month', now() AT TIME ZONE 'America/New_York')::date AS current_month
  ), months AS (
    SELECT (current_month + n * interval '1 month')::date AS month
    FROM bounds CROSS JOIN generate_series(-5, 0) AS s(n)
  ), test_accounts AS (
    SELECT user_id FROM hocalist.stripe_live_billing_pilot
    UNION SELECT buyer_id FROM hocalist.sandbox_reward_credits
    UNION SELECT user_id FROM hocalist.withdrawal_requests WHERE provider = 'stripe_global_sandbox'
  ), accounts AS (
    SELECT u.id, CASE
      WHEN t.user_id IS NOT NULL OR u.raw_app_meta_data->>'hocalist_reporting_cohort' = 'test' THEN 'test'
      WHEN u.raw_app_meta_data->>'hocalist_reporting_cohort' = 'real' THEN 'real'
      ELSE 'unclassified' END AS cohort
    FROM auth.users u LEFT JOIN test_accounts t ON t.user_id = u.id
  ), events AS (
    SELECT 'requests' AS kind, created_at AS occurred_at, buyer_user_id AS buyer_id, NULL::uuid AS seller_id
    FROM hocalist.requests
    UNION ALL SELECT 'offers', created_at, buyer_user_id, seller_user_id FROM hocalist.offers
    UNION ALL SELECT 'confirmations', confirmed_at, buyer_user_id, seller_user_id FROM hocalist.sale_confirmations
  ), activity_counts AS (
    SELECT date_trunc('month', e.occurred_at AT TIME ZONE 'America/New_York')::date AS month,
      e.kind, CASE WHEN b.cohort = 'test' OR s.cohort = 'test' THEN 'test'
        WHEN b.cohort = 'real' AND (e.kind = 'requests' OR s.cohort = 'real') THEN 'real'
        ELSE 'unclassified' END AS cohort, count(*) AS total
    FROM events e
    LEFT JOIN accounts b ON b.id = e.buyer_id
    LEFT JOIN accounts s ON s.id = e.seller_id
    WHERE e.occurred_at >= (SELECT min(month)::timestamp AT TIME ZONE 'America/New_York' FROM months)
      AND e.occurred_at <= now()
    GROUP BY 1,2,3
  ), activity_by_cohort AS (
    SELECT m.month, c.cohort, jsonb_object_agg(k.kind, coalesce(a.total, 0)) AS totals
    FROM months m CROSS JOIN (VALUES ('real'), ('test'), ('unclassified')) c(cohort)
    CROSS JOIN (VALUES ('requests'), ('offers'), ('confirmations')) k(kind)
    LEFT JOIN activity_counts a ON (a.month, a.cohort, a.kind) = (m.month, c.cohort, k.kind)
    GROUP BY 1,2
  ), activity AS (
    SELECT month, jsonb_object_agg(cohort, totals) AS cohorts FROM activity_by_cohort GROUP BY month
  ), deposits AS (
    SELECT date_trunc('month', p.verified_at AT TIME ZONE 'America/New_York')::date AS month,
      sum(p.amount_minor) FILTER (WHERE pilot.user_id IS NULL) AS customer_minor,
      sum(p.amount_minor) FILTER (WHERE pilot.user_id IS NOT NULL) AS pilot_minor
    FROM hocalist.stripe_live_credit_payments p
    JOIN hocalist.credit_batches b ON b.id = p.wallet_batch_id AND b.live_billing
    LEFT JOIN hocalist.stripe_live_billing_pilot pilot ON pilot.user_id = b.user_id
    WHERE p.verified_at >= (SELECT min(month)::timestamp AT TIME ZONE 'America/New_York' FROM months)
      AND p.verified_at <= now()
    GROUP BY 1
  ), payouts AS (
    SELECT date_trunc('month', paid.paid_at AT TIME ZONE 'America/New_York')::date AS month,
      count(*) AS payout_count, count(DISTINCT w.user_id) AS paid_buyers,
      sum(w.net_minor) AS paid_net, sum(w.fee_minor) AS deductions
    FROM hocalist.withdrawal_requests w
    JOIN LATERAL (
      SELECT min(e.created_at) AS paid_at FROM hocalist.withdrawal_events e
      WHERE e.withdrawal_id = w.id AND e.event = 'paid'
    ) paid ON true
    WHERE w.status = 'paid' AND w.provider = 'stripe_global_live'
      AND NOT EXISTS (SELECT 1 FROM accounts a WHERE a.id = w.user_id AND a.cohort = 'test')
      AND paid.paid_at >= (SELECT min(month)::timestamp AT TIME ZONE 'America/New_York' FROM months)
      AND paid.paid_at <= now()
    GROUP BY 1
  ), observed_invoices AS (
    SELECT stripe_account_id AS account_id, stripe_object_id AS invoice_id,
      date_trunc('month', to_timestamp(min(stripe_created)) AT TIME ZONE 'America/New_York')::date AS month,
      bool_or(handling_state = 'verified') AS verified,
      coalesce(bool_or(a.cohort = 'test'), false) AS test
    FROM hocalist.stripe_live_billing_receipts receipt
    LEFT JOIN accounts a ON a.id = receipt.user_id
    WHERE event_type = 'invoice.paid' AND left(stripe_object_id, 3) = 'in_'
      AND stripe_created <= extract(epoch FROM now())
    GROUP BY 1,2
  ), subscriptions AS (
    SELECT coalesce(r.paid_month, i.month) AS month,
      CASE WHEN bool_and(i.verified AND r.invoice_id IS NOT NULL)
        THEN sum(CASE WHEN i.test THEN 0 ELSE r.customer_revenue_minor END) END AS amount
    FROM observed_invoices i LEFT JOIN hocalist.admin_finance_stripe_invoices r USING (account_id, invoice_id)
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'capturedAt', now(),
    'months', jsonb_agg(jsonb_build_object(
      'month', to_char(m.month, 'YYYY-MM'), 'deposits', coalesce(d.customer_minor, 0),
      'excludedPilotDeposits', coalesce(d.pilot_minor, 0),
      'paidNet', coalesce(p.paid_net, 0), 'paidBuyers', coalesce(p.paid_buyers, 0),
      'payoutCount', coalesce(p.payout_count, 0), 'payoutDeductions', coalesce(p.deductions, 0),
      'activity', a.cohorts, 'revision', coalesce(entry.revision, 0), 'note', entry.note,
      'totals', jsonb_build_object('targeting', null, 'confirmation', null, 'stripeFees', null,
        'refunds', null, 'rewardsEarned', null, 'overhead', null) ||
        coalesce(entry.totals, '{}'::jsonb) || jsonb_build_object('subscriptions', s.amount),
      'subscriptionReconciled', s.amount IS NOT NULL
    ) ORDER BY m.month),
    'processingGross', (SELECT coalesce(sum(w.amount_minor), 0) FROM hocalist.withdrawal_requests w
      WHERE w.provider = 'stripe_global_live' AND w.status = 'processing'
        AND NOT EXISTS (SELECT 1 FROM accounts a WHERE a.id = w.user_id AND a.cohort = 'test')),
    'sandboxPaidPayouts', (SELECT count(*) FROM hocalist.withdrawal_requests
      WHERE provider = 'stripe_global_sandbox' AND status = 'paid')
  ) INTO result
  FROM months m LEFT JOIN deposits d USING (month) LEFT JOIN payouts p USING (month)
  LEFT JOIN activity a USING (month) LEFT JOIN subscriptions s USING (month)
  LEFT JOIN LATERAL (
    SELECT x.revision, x.totals, x.note FROM hocalist.admin_finance_month_entries x
    WHERE x.month = m.month ORDER BY x.revision DESC LIMIT 1
  ) entry ON true;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION hocalist.admin_finance_assert_access(),
  hocalist.admin_finance_overview(), hocalist.admin_finance_save_month(date, integer, jsonb, text)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_finance_overview(),
  hocalist.admin_finance_save_month(date, integer, jsonb, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

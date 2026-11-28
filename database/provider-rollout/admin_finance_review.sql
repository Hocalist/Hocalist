-- Read-only snapshot for private review. Export aggregate results only.
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
), invoice_receipts AS (
  SELECT md5(coalesce(string_agg(DISTINCT stripe_account_id || '/' || stripe_object_id,
    ',' ORDER BY stripe_account_id || '/' || stripe_object_id), '')) AS fingerprint
  FROM hocalist.stripe_live_billing_receipts WHERE event_type = 'invoice.paid'
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
    AND paid.paid_at >= (SELECT min(month)::timestamp AT TIME ZONE 'America/New_York' FROM months)
    AND paid.paid_at <= now()
  GROUP BY 1
)
SELECT jsonb_build_object(
  'capturedAt', now(),
  'invoiceFingerprint', (SELECT fingerprint FROM invoice_receipts),
  'report', jsonb_build_object(
    'months', jsonb_agg(jsonb_build_object(
      'month', to_char(m.month, 'YYYY-MM'), 'deposits', coalesce(d.customer_minor, 0),
      'excludedPilotDeposits', coalesce(d.pilot_minor, 0), 'paidNet', coalesce(p.paid_net, 0),
      'paidBuyers', coalesce(p.paid_buyers, 0), 'payoutCount', coalesce(p.payout_count, 0),
      'activity', a.cohorts,
      'payoutDeductions', coalesce(p.deductions, 0), 'revision', 0, 'totals', null, 'note', null
    ) ORDER BY m.month),
    'processingGross', (SELECT coalesce(sum(amount_minor), 0) FROM hocalist.withdrawal_requests
      WHERE provider = 'stripe_global_live' AND status = 'processing')
  ),
  'sandboxPaidPayouts', (SELECT count(*) FROM hocalist.withdrawal_requests
    WHERE provider = 'stripe_global_sandbox' AND status = 'paid')
) AS review
FROM months m LEFT JOIN deposits d USING (month) LEFT JOIN payouts p USING (month)
LEFT JOIN activity a USING (month);

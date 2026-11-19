-- Add all current holds to the seller's existing wallet read. The recent
-- activity window and the wallet's access and settlement rules stay intact.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $migration$
DECLARE
  definition text := pg_get_functiondef('hocalist.commercial_credit_wallet()'::regprocedure);
  anchor text := '''targets'',coalesce(';
  holds text := $projection$
    'reserved_offers',coalesce((
      WITH allocations AS (
        SELECT j.target_id, sum(a.amount_minor) AS held
        FROM hocalist.paygo_credit_allocations a
        JOIN hocalist.paygo_charges j ON j.id=a.charge_id
        JOIN hocalist.credit_targets t ON t.id=j.target_id AND t.user_id=u
        WHERE a.state='reserved'
        GROUP BY j.target_id
      )
      SELECT jsonb_agg(jsonb_build_object(
        'request_title',q.title,'request_id',t.request_id,'offer_id',t.offer_id,
        'held_minor',t.reserved_minor+coalesce(a.held,0),'charged_minor',t.charged_minor,
        'next_step',CASE
          WHEN a.held>0 THEN 'payment'
          WHEN m.status IN ('accepted','reschedule_proposed') AND m.meeting_expires_at>now() THEN 'meeting'
          WHEN t.elite_deferred_initial AND t.qualified_at IS NOT NULL THEN 'elite_outcome'
          WHEN t.charged_minor>0 THEN 'remaining_fee'
          WHEN o.status='submitted' THEN 'buyer_response'
          ELSE 'offer_outcome' END
      ) ORDER BY t.created_at DESC,t.id)
      FROM hocalist.credit_targets t
      JOIN hocalist.requests q ON q.id=t.request_id
      LEFT JOIN hocalist.offers o ON o.id=t.offer_id
      LEFT JOIN allocations a ON a.target_id=t.id
      LEFT JOIN LATERAL (
        SELECT m.status,m.meeting_expires_at FROM hocalist.meetings m
        WHERE m.offer_id=t.offer_id AND m.seller_user_id=u
        ORDER BY m.updated_at DESC,m.id DESC LIMIT 1
      ) m ON true
      WHERE t.user_id=u AND t.reserved_minor+coalesce(a.held,0)>0
    ),'[]'::jsonb),
  $projection$;
BEGIN
  IF strpos(definition,'''reserved_offers''')>0 THEN RETURN; END IF;
  IF strpos(definition,anchor)=0 THEN RAISE EXCEPTION 'Wallet history projection missing'; END IF;
  EXECUTE replace(definition,anchor,holds || anchor);
END $migration$;
COMMIT;

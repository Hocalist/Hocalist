-- October audit repairs. Local reviewed upgrade; apply only after approval.
-- Existing requests/ledgers are not modified. No consent is backfilled.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $guard$
DECLARE item record;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('hocalist.marketplace_request(uuid)', 'edb014a6987ac4f669845c43bd0276e7'),
    ('hocalist.marketplace_offer_json(uuid)', '8e8e44b15f9012a0579c97f438f1af91'),
    ('hocalist.marketplace_lead_json(uuid)', '2a60bdd929941d7e0e522191f4c3cf71')
  ) AS functions(signature, hash) LOOP
    IF to_regprocedure(item.signature) IS NULL OR
       (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid=to_regprocedure(item.signature)) IS DISTINCT FROM item.hash THEN
      RAISE EXCEPTION 'Audit prerequisite drift: %',item.signature;
    END IF;
  END LOOP;
  IF to_regprocedure('hocalist.chat_assert_participant(uuid,uuid)') IS NULL OR
     to_regclass('hocalist.sale_confirmations') IS NULL THEN
    RAISE EXCEPTION 'Audit repairs require reviewed chat and sale confirmations';
  END IF;
END $guard$;

-- Add non-private authoritative metadata without changing projection scope.
DO $metadata$
DECLARE body text;
BEGIN
  SELECT prosrc INTO body FROM pg_proc WHERE oid='hocalist.marketplace_offer_json(uuid)'::regprocedure;
  body := replace(body, '''request_id'', o.request_id,', '''request_id'', o.request_id, ''request_title'', q.title,');
  EXECUTE 'CREATE OR REPLACE FUNCTION hocalist.marketplace_offer_json(p_offer uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='''' AS ' || quote_literal(body);
  SELECT prosrc INTO body FROM pg_proc WHERE oid='hocalist.marketplace_lead_json(uuid)'::regprocedure;
  body := replace(body, '''published_at'', r.created_at)', '''published_at'', r.created_at, ''verified_purchase_count'', (SELECT count(*) FROM hocalist.sale_confirmations s WHERE s.buyer_user_id=r.buyer_user_id))');
  EXECUTE 'CREATE OR REPLACE FUNCTION hocalist.marketplace_lead_json(p_request uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='''' AS ' || quote_literal(body);
END $metadata$;

-- A completed negotiation retains only the existing seller-safe request view.
-- Chat participation, role, restrictions, revocation and block rules still apply.
CREATE OR REPLACE FUNCTION hocalist.marketplace_request(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid := auth.uid(); owner_id uuid; state text; expires timestamptz; conversation_id uuid;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  SELECT buyer_user_id,status,acceptance_expires_at INTO owner_id,state,expires FROM hocalist.requests WHERE id=p_request;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found' USING ERRCODE='P0002'; END IF;
  IF owner_id=u THEN
    PERFORM hocalist.marketplace_assert_role(u,'buyer');
    RETURN hocalist.marketplace_request_json(p_request);
  END IF;
  PERFORM hocalist.marketplace_assert_role(u,'seller');
  IF state='active' AND (expires IS NULL OR now()<expires) THEN
    RETURN hocalist.marketplace_lead_json(p_request);
  END IF;
  FOR conversation_id IN SELECT c.id FROM hocalist.conversations c
    JOIN hocalist.conversation_members m ON m.conversation_id=c.id AND m.user_id=u AND m.revoked_at IS NULL
    WHERE c.request_id=p_request AND c.origin='targeted_request'
  LOOP
    BEGIN
      PERFORM hocalist.chat_assert_participant(conversation_id,u);
      RETURN hocalist.marketplace_lead_json(p_request);
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
  RAISE EXCEPTION 'request_access_denied' USING ERRCODE='42501';
END $$;

-- Counts cover the caller's full history, independent of paginated rows.
-- Attention means an unresolved proposal from the other participant.
CREATE FUNCTION hocalist.commercial_deal_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid := auth.uid(); result jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_role(u,'buyer');
  SELECT jsonb_build_object(
    'completed',(SELECT count(*) FROM hocalist.sale_confirmations WHERE buyer_user_id=u),
    'active',(SELECT count(*) FROM hocalist.meetings m WHERE m.buyer_user_id=u AND m.status<>'cancelled'
      AND NOT EXISTS(SELECT 1 FROM hocalist.sale_confirmations s WHERE s.meeting_id=m.id)),
    'attention',(SELECT count(DISTINCT m.id) FROM hocalist.meetings m
      JOIN hocalist.meeting_schedule_revisions r ON r.meeting_id=m.id AND r.status='proposed' AND r.proposed_by_user_id<>u
      WHERE m.buyer_user_id=u AND m.status IN ('proposed','reschedule_proposed')
      AND NOT EXISTS(SELECT 1 FROM hocalist.sale_confirmations s WHERE s.meeting_id=m.id))
  ) INTO result;
  RETURN result;
END $$;

-- Canonical Store link read. It returns no private contacts, images, drafts,
-- pending moderation, paused listings, or identity details of an empty store.
CREATE FUNCTION hocalist.public_store(p_seller uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE seller_name text; seller_area text; items jsonb;
BEGIN
  SELECT p.display_name,p.area_label INTO seller_name,seller_area
    FROM hocalist.memberships m JOIN hocalist.role_profiles p ON p.membership_id=m.id
    WHERE m.id=p_seller AND m.role='seller' AND m.status='active'
      AND NOT EXISTS(SELECT 1 FROM hocalist.memberships bad WHERE bad.user_id=m.user_id AND bad.status IN ('restricted','disabled'));
  IF NOT FOUND THEN RETURN jsonb_build_object('available',false); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',l.id,'kind',l.kind,'title',l.title,
      'description',l.description,'price_label',l.price_label,'service_area',l.service_area,
      'category_label',l.category_label) ORDER BY l.created_at DESC,l.id DESC),'[]'::jsonb)
    INTO items FROM (SELECT * FROM hocalist.store_listings WHERE seller_profile_id=p_seller
      AND status='active' AND moderation_status='approved' ORDER BY created_at DESC,id DESC LIMIT 50) l;
  IF jsonb_array_length(items)=0 THEN RETURN jsonb_build_object('available',false); END IF;
  RETURN jsonb_build_object('available',true,'name',seller_name,'area',seller_area,'items',items);
END $$;
REVOKE ALL ON FUNCTION hocalist.commercial_deal_summary() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION hocalist.commercial_deal_summary() TO authenticated;
REVOKE ALL ON FUNCTION hocalist.public_store(uuid) FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA hocalist TO anon;
GRANT EXECUTE ON FUNCTION hocalist.public_store(uuid) TO anon,authenticated;
-- Replacing helpers preserves their existing internal-only grants.
NOTIFY pgrst,'reload schema';
COMMIT;

-- Final coexistence verification for the complete Hocalist guarded rollout.
--
-- Read-only. Run after every dependent bundle has been applied and verified.
-- It proves the eleven live-API signatures are installed with the reviewed
-- authenticated-only grants, that the last media-gateway replacement still
-- dispatches to the chat/profile/review read rules, and that the activation
-- switches and shipped-empty policy tables stayed off/empty.
--
-- PGlite single-connection proof only; live PostgREST/JWT behavior and
-- capability activation remain separate gates.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15s';
DO $hocalist_final_verify$
DECLARE
  v_signature text;
  v_gateway text;
  v_issues text[] := ARRAY[]::text[];
BEGIN
  -- 1. The eleven RPC signatures that the live Data API probes returned as
  --    unavailable before this rollout. Authenticated-only, never anon or
  --    service_role.
  FOREACH v_signature IN ARRAY ARRAY[
    'account_lifecycle_status()',
    'hocatrends_trends(integer)',
    'marketplace_seller_outcomes(integer)',
    'chat_block_state(uuid)',
    'chat_search_inbox(text,integer,text)',
    'call_status(uuid,bigint)',
    'member_avatar(uuid)',
    'admin_commercial_config()',
    'website_purchase_status(uuid)',
    'commercial_credit_wallet()',
    'commercial_reward_wallet()'] LOOP
    IF to_regprocedure('hocalist.' || v_signature) IS NULL THEN
      v_issues := array_append(v_issues, 'missing RPC: hocalist.' || v_signature);
    ELSIF NOT has_function_privilege('authenticated', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE')
       OR has_function_privilege('anon', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE')
       OR has_function_privilege('service_role', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'grant drift: hocalist.' || v_signature);
    END IF;
  END LOOP;

  -- 2. Companion signatures from the same pending bundles whose later
  --    supersession keeps their own verify scripts step-local (media 101,
  --    chat 011, admin 061-063, upgrade outputs). Authenticated-only unless
  --    listed as server-only.
  FOREACH v_signature IN ARRAY ARRAY[
    'chat_send_attachment(uuid,text,text,jsonb)',
    'profile_avatar_update(text,text,bigint,uuid)',
    'admin_credit_summary(integer,uuid)',
    'admin_reward_summary(integer,uuid)',
    'admin_credit_detail(uuid)',
    'admin_delivery_overview()',
    'admin_call_settings_history()',
    'chat_block(uuid,text)',
    'chat_unblock(uuid)',
    'chat_search(text,integer,text,uuid)',
    'withdrawal_status()',
    'verification_submit(text,jsonb)',
    'verification_status()',
    'restriction_appeal_submit(text,jsonb)',
    'account_health_status()',
    'credit_deposit_status()'] LOOP
    IF to_regprocedure('hocalist.' || v_signature) IS NULL THEN
      v_issues := array_append(v_issues, 'missing RPC: hocalist.' || v_signature);
    ELSIF NOT has_function_privilege('authenticated', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE')
       OR has_function_privilege('anon', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE')
       OR has_function_privilege('service_role', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'grant drift: hocalist.' || v_signature);
    END IF;
  END LOOP;

  -- Server-only contracts must stay off the client roles.
  FOREACH v_signature IN ARRAY ARRAY[
    'website_checkout_context(text)',
    'media_cleanup_hash(integer,jsonb,jsonb)'] LOOP
    IF to_regprocedure('hocalist.' || v_signature) IS NULL THEN
      v_issues := array_append(v_issues, 'missing RPC: hocalist.' || v_signature);
    ELSIF has_function_privilege('authenticated', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE')
       OR has_function_privilege('anon', ('hocalist.' || v_signature)::regprocedure, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'client grant on server contract: hocalist.' || v_signature);
    END IF;
  END LOOP;

  -- 3. Account 132 is the last migration that replaces the media gateway.
  --    Verify it kept the chat 011 and media 101 dispatch clauses.
  IF to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)') IS NULL THEN
    v_issues := array_append(v_issues, 'media gateway is missing');
  ELSE
    v_gateway := pg_get_functiondef(to_regprocedure('hocalist.media_gateway(uuid,text,jsonb)'));
    IF position('media_read_chat' IN v_gateway) = 0
       OR position('media_read_profile' IN v_gateway) = 0
       OR position('media_read_review_evidence' IN v_gateway) = 0 THEN
      v_issues := array_append(v_issues, 'media gateway dispatch clauses were dropped');
    END IF;
  END IF;

  -- 4. Activation stays off: optional calls never enabled, deposit and reward
  --    policy ships empty, and the waitlist intake secret stays unconfigured.
  IF (SELECT enabled FROM hocalist.call_settings WHERE singleton) IS DISTINCT FROM false THEN
    v_issues := array_append(v_issues, 'calls must remain off after rollout');
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.credit_deposit_options) THEN
    v_issues := array_append(v_issues, 'credit deposit options must ship empty');
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.reward_policy) THEN
    v_issues := array_append(v_issues, 'reward policy must ship empty');
  END IF;
  IF (SELECT intake_token_hash FROM hocalist.website_waitlist_config WHERE singleton) IS NOT NULL THEN
    v_issues := array_append(v_issues, 'waitlist intake must stay unconfigured');
  END IF;

  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist final rollout verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END $hocalist_final_verify$;
SELECT 'PASS: final Hocalist rollout coexistence verification' AS hocalist_final_verify;
ROLLBACK;

-- Hocalist chat rollout: guarded single-transaction apply of the persistent
-- text-chat foundation (drafts 010).
--
-- Prerequisites already deployed and preserved (never re-run here): account
-- 003/004, Stripe receipt 005, billing 006 and push 007. API schema exposure
-- and Realtime publication are dashboard settings and are NOT mutated.
--
-- On any drift or pre-existing chat object the guard aborts the whole
-- transaction; nothing is dropped, cascaded or overwritten. The DO blocks are
-- textually identical to preflight.sql and verify.sql;
-- database/chat/tests/chat_rollout.test.mjs asserts this.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $hocalist_chat_guard$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_required_relations constant text[] := ARRAY[
    'profiles','memberships','role_profiles','profile_contacts','command_receipts',
    'stripe_test_inbox','stripe_test_plans','stripe_test_customers','stripe_test_checkouts',
    'stripe_test_subscriptions','stripe_test_worker_lock',
    'push_devices','notifications','push_deliveries'];
  v_chat_relations constant text[] := ARRAY[
    'conversations','conversation_members','conversation_messages'];
  v_required_functions constant text[] := ARRAY[
    'handle_new_user()',
    'receive_stripe_test_event(text,text,text,text,bigint,boolean)',
    'account_command(text,text,jsonb)',
    'stripe_test_checkout_begin(uuid,text,uuid)',
    'stripe_test_checkout_bind(uuid,text,text,text)',
    'stripe_test_checkout_expire(uuid,text,text)',
    'stripe_test_claim()','stripe_test_customer_context(text)',
    'stripe_test_finish(uuid,text,text,jsonb,text)','stripe_test_billing_status()',
    'push_device_register(uuid,text,text,boolean)','push_device_disable(uuid,text)',
    'notification_enqueue(uuid,uuid,text,uuid)','push_claim()',
    'push_delivery_target(uuid,uuid)','push_finish(uuid,uuid,text,integer)'];
  v_chat_functions constant text[] := ARRAY[
    'chat_inbox(integer,text)','chat_conversation(uuid)','chat_messages(uuid,integer,uuid)',
    'chat_send(uuid,text,text)','chat_mark_read(uuid,uuid)','chat_set_muted(uuid,boolean)',
    'chat_assert_participant(uuid,uuid)','chat_conversation_json(uuid)','chat_is_member(uuid,uuid)',
    'chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)'];
  -- Optional independently deployed Places module: exact names, verified below.
  v_places_relations constant text[] := ARRAY[
    'places_search_sessions','places_search_suggestions','places_rate_counters'];
  v_places_functions constant text[] := ARRAY[
    'places_gate(uuid,text,uuid,text,text)',
    'places_record_suggestions(uuid,uuid,text[])',
    'places_resolve_session(uuid,uuid)','places_release_session(uuid,uuid)',
    'places_rate_bump(text,text,text,timestamp with time zone)'];
  v_rel text;
  v_fn text;
BEGIN
  IF to_regnamespace('hocalist') IS NULL THEN
    v_issues := array_append(v_issues, 'hocalist schema is missing');
  ELSE
    IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname='hocalist')
       IS DISTINCT FROM 'postgres' THEN
      v_issues := array_append(v_issues, 'hocalist schema owner is not postgres');
    END IF;
    IF NOT has_schema_privilege('authenticated','hocalist','USAGE')
       OR NOT has_schema_privilege('service_role','hocalist','USAGE')
       OR has_schema_privilege('anon','hocalist','USAGE')
       OR has_schema_privilege('anon','hocalist','CREATE')
       OR has_schema_privilege('authenticated','hocalist','CREATE')
       OR has_schema_privilege('service_role','hocalist','CREATE') THEN
      v_issues := array_append(v_issues, 'hocalist schema access differs from the reviewed baseline');
    END IF;
  END IF;

  -- Relations: required present, chat absent, nothing else unexpected.
  FOREACH v_rel IN ARRAY v_required_relations LOOP
    IF to_regclass('hocalist.' || v_rel) IS NULL THEN
      v_issues := array_append(v_issues, 'missing baseline relation: hocalist.' || v_rel);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_rel)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: hocalist.' || v_rel);
    END IF;
  END LOOP;
  FOR v_rel IN
    SELECT c.relname FROM pg_class c
    WHERE c.relnamespace = to_regnamespace('hocalist')
      AND c.relkind IN ('r','p','v','m','S','f')
  LOOP
    IF v_rel = ANY(v_chat_relations) THEN
      v_issues := array_append(v_issues, 'chat relation already exists: ' || v_rel);
    ELSIF NOT (v_rel = ANY(v_required_relations) OR v_rel = ANY(v_places_relations)) THEN
      v_issues := array_append(v_issues, 'unexpected relation in hocalist: ' || v_rel);
    END IF;
  END LOOP;

  -- Functions: required present, chat absent, nothing else unexpected.
  FOREACH v_fn IN ARRAY v_required_functions LOOP
    IF to_regprocedure('hocalist.' || v_fn) IS NULL THEN
      v_issues := array_append(v_issues, 'missing baseline function: ' || v_fn);
    END IF;
  END LOOP;
  FOR v_fn IN
    SELECT p.proname || '(' || replace(oidvectortypes(p.proargtypes), ', ', ',') || ')'
    FROM pg_proc p WHERE p.pronamespace = to_regnamespace('hocalist')
  LOOP
    IF v_fn = ANY(v_chat_functions) THEN
      v_issues := array_append(v_issues, 'chat function already exists: ' || v_fn);
    ELSIF NOT (v_fn = ANY(v_required_functions) OR v_fn = ANY(v_places_functions)) THEN
      v_issues := array_append(v_issues, 'unexpected function in hocalist: ' || v_fn);
    END IF;
  END LOOP;

  -- Focused ACL invariants for the deployed account, billing and push state.
  IF to_regclass('hocalist.memberships') IS NOT NULL
     AND to_regclass('hocalist.role_profiles') IS NOT NULL
     AND to_regclass('hocalist.profile_contacts') IS NOT NULL
     AND to_regclass('hocalist.command_receipts') IS NOT NULL
     AND to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NOT NULL THEN
    IF NOT has_table_privilege('authenticated','hocalist.memberships','SELECT')
       OR NOT has_table_privilege('authenticated','hocalist.role_profiles','SELECT')
       OR NOT has_table_privilege('authenticated','hocalist.profile_contacts','SELECT')
       OR has_table_privilege('authenticated','hocalist.memberships','INSERT')
       OR has_table_privilege('authenticated','hocalist.command_receipts','SELECT')
       OR has_table_privilege('anon','hocalist.memberships','SELECT')
       OR has_table_privilege('service_role','hocalist.memberships','SELECT') THEN
      v_issues := array_append(v_issues, 'account table grants differ from the reviewed rollout');
    END IF;
    IF NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
       OR has_function_privilege('anon','hocalist.account_command(text,text,jsonb)','EXECUTE')
       OR has_function_privilege('service_role','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
      v_issues := array_append(v_issues, 'account_command grants differ from the reviewed rollout');
    END IF;
  END IF;
  IF to_regclass('hocalist.stripe_test_inbox') IS NOT NULL
     AND to_regprocedure('hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)') IS NOT NULL THEN
    IF NOT has_function_privilege('service_role','hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)','EXECUTE')
       OR has_function_privilege('authenticated','hocalist.receive_stripe_test_event(text,text,text,text,bigint,boolean)','EXECUTE')
       OR has_table_privilege('service_role','hocalist.stripe_test_inbox','SELECT') THEN
      v_issues := array_append(v_issues, 'stripe receipt grants differ from the reviewed rollout');
    END IF;
  END IF;
  IF to_regprocedure('hocalist.stripe_test_billing_status()') IS NOT NULL
     AND to_regprocedure('hocalist.stripe_test_checkout_begin(uuid,text,uuid)') IS NOT NULL
     AND to_regprocedure('hocalist.stripe_test_claim()') IS NOT NULL
     AND to_regclass('hocalist.stripe_test_checkouts') IS NOT NULL THEN
    IF NOT has_function_privilege('authenticated','hocalist.stripe_test_billing_status()','EXECUTE')
       OR has_function_privilege('authenticated','hocalist.stripe_test_checkout_begin(uuid,text,uuid)','EXECUTE')
       OR NOT has_function_privilege('service_role','hocalist.stripe_test_claim()','EXECUTE')
       OR has_table_privilege('authenticated','hocalist.stripe_test_checkouts','SELECT') THEN
      v_issues := array_append(v_issues, 'billing grants differ from the reviewed rollout');
    END IF;
  END IF;
  IF to_regclass('hocalist.notifications') IS NOT NULL
     AND to_regclass('hocalist.push_devices') IS NOT NULL
     AND to_regprocedure('hocalist.push_device_register(uuid,text,text,boolean)') IS NOT NULL
     AND to_regprocedure('hocalist.push_claim()') IS NOT NULL THEN
    IF NOT has_table_privilege('authenticated','hocalist.notifications','SELECT')
       OR has_table_privilege('authenticated','hocalist.push_devices','SELECT')
       OR NOT has_function_privilege('authenticated','hocalist.push_device_register(uuid,text,text,boolean)','EXECUTE')
       OR NOT has_function_privilege('service_role','hocalist.push_claim()','EXECUTE')
       OR has_function_privilege('authenticated','hocalist.push_claim()','EXECUTE') THEN
      v_issues := array_append(v_issues, 'push grants differ from the reviewed rollout');
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='auth.users'::regclass AND t.tgname='on_auth_user_created'
      AND t.tgfoid=to_regprocedure('hocalist.handle_new_user()')
      AND t.tgtype=5 AND t.tgenabled='O'
  ) THEN
    v_issues := array_append(v_issues, 'signup routing trigger changed');
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_default_acl d
    WHERE pg_get_userbyid(d.defaclrole)='postgres'
      AND (d.defaclnamespace=0 OR d.defaclnamespace=to_regnamespace('hocalist'))
      AND EXISTS (
        SELECT 1 FROM aclexplode(d.defaclacl) a
        WHERE a.grantee=0 OR a.grantee IN (
          SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role'))
      )
  ) THEN
    v_issues := array_append(v_issues,
      'postgres default privileges would grant client/service access to new hocalist objects');
  END IF;


  -- If any Places object exists, require the complete reviewed module.
  IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace=to_regnamespace('hocalist')
      AND relname=ANY(v_places_relations))
     OR EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace=to_regnamespace('hocalist')
      AND proname LIKE 'places_%') THEN
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_service_functions constant text[] := ARRAY[
    'places_gate(uuid,text,uuid,text,text)',
    'places_record_suggestions(uuid,uuid,text[])',
    'places_resolve_session(uuid,uuid)',
    'places_release_session(uuid,uuid)'];
  v_tables constant text[] := ARRAY[
    'places_search_sessions','places_search_suggestions','places_rate_counters'];
  v_fn text;
  v_table text;
  v_columns text[];
  v_expected_sessions constant text[] := ARRAY[
    'token:uuid','user_id:uuid','operation_count:integer',
    'created_at:timestamp with time zone','expires_at:timestamp with time zone',
    'resolved_at:timestamp with time zone','resolving_at:timestamp with time zone'];
  v_expected_suggestions constant text[] := ARRAY[
    'session_token:uuid','place_id:text','created_at:timestamp with time zone'];
  v_expected_counters constant text[] := ARRAY[
    'scope:text','operation:text','window_kind:text',
    'bucket:timestamp with time zone','count:integer'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing places table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    ELSIF has_table_privilege('authenticated', 'hocalist.' || v_table, 'SELECT')
       OR has_table_privilege('anon', 'hocalist.' || v_table, 'SELECT') THEN
      v_issues := array_append(v_issues, 'places table is client-readable: ' || v_table);
    END IF;
  END LOOP;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_sessions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_sessions THEN
    v_issues := array_append(v_issues, 'places_search_sessions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_search_suggestions'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_suggestions THEN
    v_issues := array_append(v_issues, 'places_search_suggestions columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.places_rate_counters'::regclass
    AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_counters THEN
    v_issues := array_append(v_issues, 'places_rate_counters columns differ from the reviewed shape');
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist'
      AND table_name IN ('places_search_sessions','places_search_suggestions','places_rate_counters')
      AND column_name ~* '(query|label|address|input|display|formatted|latitude|longitude)'
  ) THEN
    v_issues := array_append(v_issues, 'places gateway must not store queries, labels or addresses');
  END IF;
  FOREACH v_fn IN ARRAY v_service_functions LOOP
    IF NOT has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'places function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  IF has_function_privilege(
       'authenticated','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE')
     OR has_function_privilege(
       'service_role','hocalist.places_rate_bump(text,text,text,timestamptz)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'internal places helper is executable');
  END IF;
  IF NOT has_function_privilege(
       'authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed account grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist places post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
;
    IF to_regprocedure('hocalist.places_rate_bump(text,text,text,timestamptz)') IS NULL THEN
      RAISE EXCEPTION 'Places internal helper missing';
    END IF;
  END IF;

  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat preflight failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_guard$;


CREATE TABLE hocalist.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin text NOT NULL CHECK (origin IN ('targeted_request','store_listing','hocatrends_enquiry')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  -- Subject ids are recorded marketplace ids. The authoritative request,
  -- offer, listing and discovery tables do not exist in hocalist yet, so
  -- these are validated by the internal opening boundary and intentionally
  -- carry no foreign keys.
  request_id uuid,
  offer_id uuid,
  listing_id uuid,
  discovery_topic_id uuid,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_origin_subject CHECK (
    (origin = 'targeted_request' AND request_id IS NOT NULL AND listing_id IS NULL AND discovery_topic_id IS NULL)
    OR (origin = 'store_listing' AND listing_id IS NOT NULL AND request_id IS NULL AND offer_id IS NULL AND discovery_topic_id IS NULL)
    OR (origin = 'hocatrends_enquiry' AND discovery_topic_id IS NOT NULL AND request_id IS NULL AND offer_id IS NULL AND listing_id IS NULL)
  )
);

CREATE TABLE hocalist.conversation_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  sender_profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  kind text NOT NULL DEFAULT 'text' CHECK (kind IN ('text','system_notice')),
  text text NOT NULL,
  client_message_id text CHECK (client_message_id IS NULL OR length(client_message_id) BETWEEN 1 AND 128),
  request_hash text,
  -- Server ordering key. Timestamps can tie; the identity sequence cannot.
  seq bigint GENERATED ALWAYS AS IDENTITY,
  sent_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_message_text CHECK (length(btrim(text)) BETWEEN 1 AND 4000),
  CONSTRAINT chat_text_message_identity CHECK (
    kind <> 'text' OR (client_message_id IS NOT NULL AND request_hash IS NOT NULL)
  )
);
CREATE UNIQUE INDEX conversation_messages_client_key
  ON hocalist.conversation_messages(conversation_id, sender_user_id, client_message_id)
  WHERE client_message_id IS NOT NULL;
CREATE INDEX conversation_messages_page ON hocalist.conversation_messages(conversation_id, seq DESC);

CREATE TABLE hocalist.conversation_members (
  conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  -- Domain profile id = membership id (account contract).
  profile_id uuid NOT NULL REFERENCES hocalist.memberships(id),
  role text NOT NULL CHECK (role IN ('buyer','seller')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  is_muted boolean NOT NULL DEFAULT false,
  last_read_seq bigint NOT NULL DEFAULT 0 CHECK (last_read_seq >= 0),
  last_read_message_id uuid REFERENCES hocalist.conversation_messages(id),
  last_read_at timestamptz,
  PRIMARY KEY (conversation_id, user_id),
  UNIQUE (conversation_id, profile_id),
  CONSTRAINT chat_member_revoked_after_join CHECK (revoked_at IS NULL OR revoked_at >= joined_at)
);

ALTER TABLE hocalist.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.conversation_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.conversation_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.conversations, hocalist.conversation_messages, hocalist.conversation_members
  FROM PUBLIC, anon, authenticated, service_role;

-- Internal helper used by the defense-in-depth policies below. SECURITY
-- DEFINER avoids RLS self-recursion when a policy checks membership.
CREATE FUNCTION hocalist.chat_is_member(p_conversation uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM hocalist.conversation_members m
    WHERE m.conversation_id = p_conversation AND m.user_id = p_user
      AND m.revoked_at IS NULL
  );
$$;

-- Defense in depth: clients have no table grants, so these policies are inert
-- today and exist so a future reviewed grant cannot expose another member's
-- rows. All functional access still goes through the RPCs below.
CREATE POLICY chat_member_conversation_read ON hocalist.conversations
  FOR SELECT TO authenticated USING (hocalist.chat_is_member(id, (SELECT auth.uid())));
CREATE POLICY chat_member_message_read ON hocalist.conversation_messages
  FOR SELECT TO authenticated USING (hocalist.chat_is_member(conversation_id, (SELECT auth.uid())));
CREATE POLICY chat_member_member_read ON hocalist.conversation_members
  FOR SELECT TO authenticated USING (hocalist.chat_is_member(conversation_id, (SELECT auth.uid())));

-- Internal helper. Not executable by any client role.
CREATE FUNCTION hocalist.chat_assert_participant(p_conversation uuid, p_user uuid)
RETURNS hocalist.conversation_members
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  m hocalist.conversation_members%ROWTYPE;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO m FROM hocalist.conversation_members
    WHERE conversation_id = p_conversation AND user_id = p_user;
  IF NOT FOUND OR m.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'conversation_access_denied' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships
                 WHERE id = m.profile_id AND user_id = p_user
                   AND role = m.role AND status = 'active') THEN
    RAISE EXCEPTION 'role_not_active' USING ERRCODE='42501';
  END IF;
  RETURN m;
END; $$;

-- Internal conversation JSON builder shared by inbox/conversation reads.
CREATE FUNCTION hocalist.chat_conversation_json(p_conversation uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', c.id,
    'origin', c.origin,
    'status', c.status,
    'request_id', c.request_id,
    'offer_id', c.offer_id,
    'listing_id', c.listing_id,
    'discovery_topic_id', c.discovery_topic_id,
    'revision', c.revision,
    'created_at', c.created_at,
    'updated_at', c.updated_at,
    'members', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', m.user_id,
        'profile_id', m.profile_id,
        'role', m.role,
        'joined_at', m.joined_at,
        'revoked_at', m.revoked_at,
        'is_muted', m.is_muted,
        'last_read_message_id', m.last_read_message_id,
        'last_read_at', m.last_read_at
      ) ORDER BY m.joined_at, m.user_id)
      FROM hocalist.conversation_members m WHERE m.conversation_id = c.id
    ), '[]'::jsonb)
  )
  FROM hocalist.conversations c WHERE c.id = p_conversation;
$$;

-- Inbox: participant rows with counterpart, latest message and unread count.
CREATE FUNCTION hocalist.chat_inbox(p_page_size integer DEFAULT 50, p_cursor text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_size integer;
  v_cursor_seq bigint;
  v_cursor_id uuid;
  v_last_seq bigint;
  v_last_id uuid;
  v_items jsonb;
  v_next text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  v_size := greatest(1, least(coalesce(p_page_size, 50), 100));
  IF p_cursor IS NOT NULL THEN
    BEGIN
      v_cursor_seq := split_part(p_cursor, '.', 1)::bigint;
      v_cursor_id := split_part(p_cursor, '.', 2)::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023';
    END;
  END IF;

  SELECT coalesce(jsonb_agg(row_json ORDER BY row_seq DESC, row_id DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT c.id AS row_id,
           coalesce(latest.seq, 0) AS row_seq,
           jsonb_build_object(
             'conversation', hocalist.chat_conversation_json(c.id),
             'counterpart_display_name', coalesce(nullif(btrim(counterpart.display_name), ''), 'Hocalist member'),
             'counterpart_profile_id', counterpart_member.profile_id,
             'latest_message', latest.message,
             'unread_count', (
               SELECT count(*)::integer FROM hocalist.conversation_messages m
               WHERE m.conversation_id = c.id AND m.seq > self.last_read_seq
                 AND m.sender_user_id <> v_user
             )
           ) AS row_json
    FROM hocalist.conversation_members self
    JOIN hocalist.conversations c ON c.id = self.conversation_id
    LEFT JOIN LATERAL (
      SELECT m.seq, to_jsonb(m) AS message FROM hocalist.conversation_messages m
      WHERE m.conversation_id = c.id ORDER BY m.seq DESC LIMIT 1
    ) latest ON true
    LEFT JOIN LATERAL (
      SELECT om.profile_id FROM hocalist.conversation_members om
      WHERE om.conversation_id = c.id AND om.user_id <> v_user
      ORDER BY om.joined_at, om.user_id LIMIT 1
    ) counterpart_member ON true
    LEFT JOIN hocalist.role_profiles counterpart ON counterpart.membership_id = counterpart_member.profile_id
    WHERE self.user_id = v_user AND self.revoked_at IS NULL
      AND EXISTS (
        SELECT 1 FROM hocalist.memberships m
        WHERE m.id = self.profile_id AND m.user_id = v_user
          AND m.role = self.role AND m.status = 'active'
      )
      AND (p_cursor IS NULL OR (coalesce(latest.seq, 0), c.id) < (v_cursor_seq, v_cursor_id))
    ORDER BY coalesce(latest.seq, 0) DESC, c.id DESC
    LIMIT v_size
  ) rows;

  v_next := NULL;
  IF jsonb_array_length(v_items) = v_size THEN
    v_last_seq := coalesce((v_items->-1->'latest_message'->>'seq')::bigint, 0);
    v_last_id := (v_items->-1->'conversation'->>'id')::uuid;
    IF EXISTS (
      SELECT 1 FROM hocalist.conversation_members self
      JOIN hocalist.conversations c ON c.id = self.conversation_id
      LEFT JOIN LATERAL (
        SELECT m.seq FROM hocalist.conversation_messages m
        WHERE m.conversation_id = c.id ORDER BY m.seq DESC LIMIT 1
      ) latest ON true
      WHERE self.user_id = v_user AND self.revoked_at IS NULL
        AND EXISTS (
          SELECT 1 FROM hocalist.memberships m
          WHERE m.id = self.profile_id AND m.user_id = v_user
            AND m.role = self.role AND m.status = 'active'
        )
        AND (coalesce(latest.seq, 0), c.id) < (v_last_seq, v_last_id)
    ) THEN
      v_next := v_last_seq::text || '.' || v_last_id::text;
    END IF;
  END IF;

  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- One conversation with its members, for participants only.
CREATE FUNCTION hocalist.chat_conversation(p_conversation uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_member hocalist.conversation_members%ROWTYPE;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, auth.uid());
  RETURN hocalist.chat_conversation_json(p_conversation);
END; $$;

-- Paged history. Newest page first internally, returned oldest-to-newest.
CREATE FUNCTION hocalist.chat_messages(
  p_conversation uuid,
  p_page_size integer DEFAULT 50,
  p_before_message uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_member hocalist.conversation_members%ROWTYPE;
  v_size integer;
  v_before_seq bigint;
  v_items jsonb;
  v_next text;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, auth.uid());
  v_size := greatest(1, least(coalesce(p_page_size, 50), 100));
  IF p_before_message IS NOT NULL THEN
    SELECT seq INTO v_before_seq FROM hocalist.conversation_messages
      WHERE id = p_before_message AND conversation_id = p_conversation;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.seq ASC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT * FROM hocalist.conversation_messages m
    WHERE m.conversation_id = p_conversation
      AND (p_before_message IS NULL OR m.seq < v_before_seq)
    ORDER BY m.seq DESC
    LIMIT v_size
  ) page;

  IF jsonb_array_length(v_items) = v_size AND EXISTS (
    SELECT 1 FROM hocalist.conversation_messages m
    WHERE m.conversation_id = p_conversation
      AND m.seq < (v_items->0->>'seq')::bigint
  ) THEN
    v_next := v_items->0->>'id';
  ELSE
    v_next := NULL;
  END IF;

  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- Idempotent text send. Same key and payload returns the stored message;
-- same key with a changed payload conflicts.
CREATE FUNCTION hocalist.chat_send(p_conversation uuid, p_key text, p_text text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
  v_message hocalist.conversation_messages%ROWTYPE;
  v_hash text;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128
     OR p_text IS NULL OR length(btrim(p_text)) NOT BETWEEN 1 AND 4000 THEN
    RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.conversations WHERE id = p_conversation AND status = 'open') THEN
    RAISE EXCEPTION 'conversation_closed' USING ERRCODE='P0001';
  END IF;
  v_hash := encode(sha256(convert_to(p_text, 'UTF8')), 'hex');
  INSERT INTO hocalist.conversation_messages(
    conversation_id, sender_user_id, sender_profile_id, kind, text, client_message_id, request_hash)
  VALUES (p_conversation, v_user, v_member.profile_id, 'text', p_text, p_key, v_hash)
  ON CONFLICT (conversation_id, sender_user_id, client_message_id)
    WHERE client_message_id IS NOT NULL DO NOTHING
  RETURNING * INTO v_message;
  IF NOT FOUND THEN
    SELECT * INTO v_message FROM hocalist.conversation_messages
      WHERE conversation_id = p_conversation AND sender_user_id = v_user AND client_message_id = p_key;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
    IF v_message.request_hash <> v_hash THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
  END IF;
  RETURN to_jsonb(v_message);
END; $$;

-- Monotonic mark-read: never moves the marker backwards, including when two
-- sessions of the same member race. The guarded UPDATE compares against the
-- current committed row after the row lock is acquired (READ COMMITTED
-- re-evaluates the WHERE on the locked row), so the older session becomes a
-- no-op instead of overwriting the newer committed position. A no-op re-reads
-- and returns the authoritative current marker so message id, sequence and
-- timestamp stay coherent.
CREATE FUNCTION hocalist.chat_mark_read(p_conversation uuid, p_last_read uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
  v_seq bigint;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_last_read IS NULL THEN RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023'; END IF;
  SELECT seq INTO v_seq FROM hocalist.conversation_messages
    WHERE id = p_last_read AND conversation_id = p_conversation;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_cursor' USING ERRCODE='22023'; END IF;
  UPDATE hocalist.conversation_members
    SET last_read_seq = v_seq, last_read_message_id = p_last_read, last_read_at = now()
    WHERE conversation_id = p_conversation AND user_id = v_user
      AND last_read_seq < v_seq
    RETURNING * INTO v_member;
  IF NOT FOUND THEN
    SELECT * INTO v_member FROM hocalist.conversation_members
      WHERE conversation_id = p_conversation AND user_id = v_user;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'conversation_access_denied' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN to_jsonb(v_member);
END; $$;

-- Per-member mute. Naturally idempotent; only the caller's own row changes.
CREATE FUNCTION hocalist.chat_set_muted(p_conversation uuid, p_muted boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_member hocalist.conversation_members%ROWTYPE;
BEGIN
  SELECT * INTO v_member FROM hocalist.chat_assert_participant(p_conversation, v_user);
  IF p_muted IS NULL THEN RAISE EXCEPTION 'invalid_message' USING ERRCODE='22023'; END IF;
  UPDATE hocalist.conversation_members SET is_muted = p_muted
    WHERE conversation_id = p_conversation AND user_id = v_user
    RETURNING * INTO v_member;
  RETURN to_jsonb(v_member);
END; $$;

-- INTERNAL transaction boundary for the later eligibility operation.
-- No client role may execute it. It validates the origin/subject shape and
-- that every participant holds the matching active membership, then creates
-- (or returns) one conversation for that origin + subject + participant set.
-- It deliberately does not charge credits, accept offers, create deals or
-- decide any pending eligibility policy.
CREATE FUNCTION hocalist.chat_open_internal(
  p_origin text,
  p_request uuid,
  p_offer uuid,
  p_listing uuid,
  p_topic uuid,
  p_participants jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_count integer;
  v_id uuid;
BEGIN
  IF p_origin NOT IN ('targeted_request','store_listing','hocatrends_enquiry') THEN
    RAISE EXCEPTION 'invalid_origin' USING ERRCODE='22023';
  END IF;
  IF NOT (
    (p_origin = 'targeted_request' AND p_request IS NOT NULL AND p_listing IS NULL AND p_topic IS NULL)
    OR (p_origin = 'store_listing' AND p_listing IS NOT NULL AND p_request IS NULL AND p_offer IS NULL AND p_topic IS NULL)
    OR (p_origin = 'hocatrends_enquiry' AND p_topic IS NOT NULL AND p_request IS NULL AND p_offer IS NULL AND p_listing IS NULL)
  ) THEN
    RAISE EXCEPTION 'invalid_subject' USING ERRCODE='22023';
  END IF;
  IF p_participants IS NULL OR jsonb_typeof(p_participants) <> 'array' THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;
  v_count := jsonb_array_length(p_participants);
  IF v_count < 2 OR v_count > 10 THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM (
      SELECT e->>'user_id' AS user_id FROM jsonb_array_elements(p_participants) e
    ) ids GROUP BY user_id HAVING count(*) > 1 OR user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_participants) e
    WHERE e->>'profile_id' IS NULL
       OR (e->>'role') IS NULL OR (e->>'role') NOT IN ('buyer','seller')
       OR NOT EXISTS (
         SELECT 1 FROM hocalist.memberships m
         WHERE m.id = (e->>'profile_id')::uuid
           AND m.user_id = (e->>'user_id')::uuid
           AND m.role = e->>'role'
           AND m.status = 'active'
       )
  ) THEN
    RAISE EXCEPTION 'invalid_participants' USING ERRCODE='22023';
  END IF;

  SELECT c.id INTO v_id FROM hocalist.conversations c
  WHERE c.origin = p_origin
    AND c.request_id IS NOT DISTINCT FROM p_request
    AND c.offer_id IS NOT DISTINCT FROM p_offer
    AND c.listing_id IS NOT DISTINCT FROM p_listing
    AND c.discovery_topic_id IS NOT DISTINCT FROM p_topic
    AND (SELECT array_agg(m.user_id ORDER BY m.user_id) FROM hocalist.conversation_members m
         WHERE m.conversation_id = c.id)
      = (SELECT array_agg((e->>'user_id')::uuid ORDER BY (e->>'user_id')::uuid)
         FROM jsonb_array_elements(p_participants) e)
  LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  INSERT INTO hocalist.conversations(origin, request_id, offer_id, listing_id, discovery_topic_id)
  VALUES (p_origin, p_request, p_offer, p_listing, p_topic)
  RETURNING id INTO v_id;
  INSERT INTO hocalist.conversation_members(conversation_id, user_id, profile_id, role)
  SELECT v_id, (e->>'user_id')::uuid, (e->>'profile_id')::uuid, e->>'role'
  FROM jsonb_array_elements(p_participants) e;
  RETURN v_id;
END; $$;

-- Client-executable surface: reads and the three writes. Nothing else.
REVOKE ALL ON FUNCTION hocalist.chat_inbox(integer,text), hocalist.chat_conversation(uuid),
  hocalist.chat_messages(uuid,integer,uuid), hocalist.chat_send(uuid,text,text),
  hocalist.chat_mark_read(uuid,uuid), hocalist.chat_set_muted(uuid,boolean),
  hocalist.chat_assert_participant(uuid,uuid), hocalist.chat_conversation_json(uuid),
  hocalist.chat_is_member(uuid,uuid),
  hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_inbox(integer,text), hocalist.chat_conversation(uuid),
  hocalist.chat_messages(uuid,integer,uuid), hocalist.chat_send(uuid,text,text),
  hocalist.chat_mark_read(uuid,uuid), hocalist.chat_set_muted(uuid,boolean)
  TO authenticated;

DO $hocalist_chat_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_table text;
  v_role text;
  v_priv text;
  v_columns text[];
  v_roles constant text[] := ARRAY['anon','authenticated','service_role'];
  v_privileges constant text[] := ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  v_chat_tables constant text[] := ARRAY['conversations','conversation_members','conversation_messages'];
  v_client_functions constant text[] := ARRAY[
    'chat_inbox(integer,text)','chat_conversation(uuid)','chat_messages(uuid,integer,uuid)',
    'chat_send(uuid,text,text)','chat_mark_read(uuid,uuid)','chat_set_muted(uuid,boolean)'];
  v_internal_functions constant text[] := ARRAY[
    'chat_assert_participant(uuid,uuid)','chat_conversation_json(uuid)',
    'chat_is_member(uuid,uuid)','chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)'];
  v_expected_conversations constant text[] := ARRAY[
    'id:uuid','origin:text','status:text','request_id:uuid','offer_id:uuid','listing_id:uuid',
    'discovery_topic_id:uuid','revision:bigint','created_at:timestamp with time zone',
    'updated_at:timestamp with time zone'];
  v_expected_messages constant text[] := ARRAY[
    'id:uuid','conversation_id:uuid','sender_user_id:uuid','sender_profile_id:uuid','kind:text',
    'text:text','client_message_id:text','request_hash:text','seq:bigint',
    'sent_at:timestamp with time zone'];
  v_expected_members constant text[] := ARRAY[
    'conversation_id:uuid','user_id:uuid','profile_id:uuid','role:text','joined_at:timestamp with time zone',
    'revoked_at:timestamp with time zone','is_muted:boolean','last_read_seq:bigint',
    'last_read_message_id:uuid','last_read_at:timestamp with time zone'];
  v_fn text;
BEGIN
  FOREACH v_table IN ARRAY v_chat_tables LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing chat table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    END IF;
  END LOOP;

  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute WHERE attrelid='hocalist.conversations'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_conversations THEN
    v_issues := array_append(v_issues, 'conversations columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute WHERE attrelid='hocalist.conversation_messages'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_messages THEN
    v_issues := array_append(v_issues, 'conversation_messages columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum) INTO v_columns
  FROM pg_attribute WHERE attrelid='hocalist.conversation_members'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_members THEN
    v_issues := array_append(v_issues, 'conversation_members columns differ from the reviewed shape');
  END IF;

  IF (SELECT count(*) FROM pg_policies WHERE schemaname='hocalist' AND tablename LIKE 'conversation%') <> 3 THEN
    v_issues := array_append(v_issues, 'unexpected chat policy set');
  END IF;

  FOREACH v_table IN ARRAY v_chat_tables LOOP
    IF EXISTS (
      SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
      WHERE c.oid=('hocalist.' || v_table)::regclass
        AND pg_get_userbyid(a.grantee) <> 'postgres'
    ) THEN
      v_issues := array_append(v_issues, 'unexpected non-owner grants on ' || v_table);
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_attribute att, aclexplode(att.attacl) a
      WHERE att.attrelid=('hocalist.' || v_table)::regclass
        AND att.attnum>0 AND NOT att.attisdropped
    ) THEN
      v_issues := array_append(v_issues, 'unexpected column grants on ' || v_table);
    END IF;
    FOREACH v_role IN ARRAY v_roles LOOP
      FOREACH v_priv IN ARRAY v_privileges LOOP
        IF has_table_privilege(v_role, 'hocalist.' || v_table, v_priv) THEN
          v_issues := array_append(v_issues,
            'unexpected ' || v_priv || ' for ' || v_role || ' on ' || v_table);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'chat function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal chat function is executable: ' || v_fn);
    END IF;
  END LOOP;

  -- Deployed account, billing and push state must be untouched.
  IF NOT has_table_privilege('authenticated','hocalist.memberships','SELECT')
     OR has_table_privilege('authenticated','hocalist.memberships','INSERT')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.stripe_test_billing_status()','EXECUTE')
     OR NOT has_table_privilege('authenticated','hocalist.notifications','SELECT')
     OR NOT has_function_privilege('service_role','hocalist.push_claim()','EXECUTE')
     OR has_table_privilege('service_role','hocalist.stripe_test_inbox','SELECT') THEN
    v_issues := array_append(v_issues, 'deployed account/billing/push grants changed');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='auth.users'::regclass AND t.tgname='on_auth_user_created'
      AND t.tgfoid=to_regprocedure('hocalist.handle_new_user()') AND t.tgenabled='O'
  ) THEN
    v_issues := array_append(v_issues, 'signup routing trigger changed');
  END IF;

  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist chat post-apply verification failed: %', array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_chat_postapply$;
COMMIT;
SELECT 'PASS: chat foundation applied and verified' AS chat_rollout;

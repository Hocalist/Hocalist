-- Hocalist meeting rollout: guarded single-transaction apply of the meeting
-- and reschedule foundation (draft 040). This file is the reviewed draft with
-- this header; database/meetings/tests/meetings_rollout.test.mjs asserts the
-- draft text is present verbatim.
--
-- Prerequisites already deployed and preserved (never re-run here): account
-- 003/004, chat 010 and marketplace 020 (the schedule normalizer and
-- next-local-day helper are reused). This bundle never issues or verifies a
-- buyer PIN; PIN policy remains an unresolved owner decision.
--
-- Meeting mutations carry client operation keys and replay committed receipts,
-- so a lost-response retry is safe and a changed payload under the same key is
-- refused.
--
-- On any drift or pre-existing meeting object the guard aborts the whole
-- transaction; nothing is dropped, cascaded or overwritten.
-- DRAFT: meeting and reschedule foundation.
--
-- Adds participant-authorized meetings tied to an accepted offer in a deal
-- conversation, with immutable schedule revisions, accept/reject, reschedule
-- proposals with stale-revision protection, cancellation and the exclusive
-- next-local-midnight expiry in the accepted IANA zone. It deliberately does
-- NOT issue, store or verify a buyer PIN: PIN policy (length, attempts,
-- sensitive handling) is an unresolved owner decision and stays gated.
--
-- Not an instruction to apply to a live project. Apply only through the
-- guarded bundle in database/meetings/rollout after coordinating review.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $meeting_guard$
BEGIN
  IF to_regclass('hocalist.profiles') IS NULL
     OR to_regclass('hocalist.memberships') IS NULL
     OR to_regclass('hocalist.conversations') IS NULL
     OR to_regclass('hocalist.conversation_members') IS NULL
     OR to_regclass('hocalist.offers') IS NULL
     OR to_regprocedure('hocalist.account_command(text,text,jsonb)') IS NULL
     OR to_regprocedure('hocalist.marketplace_valid_timezone(text)') IS NULL
     OR to_regprocedure('hocalist.marketplace_next_local_day_start(date,text)') IS NULL THEN
    RAISE EXCEPTION 'Account/chat/marketplace foundation is missing';
  END IF;
  IF to_regclass('hocalist.meetings') IS NOT NULL
     OR to_regclass('hocalist.meeting_receipts') IS NOT NULL
     OR to_regprocedure('hocalist.meeting_propose(uuid,jsonb,text)') IS NOT NULL
     OR to_regprocedure('hocalist.meeting_propose(uuid,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Meeting objects already exist; review before applying';
  END IF;
END
$meeting_guard$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One deal meeting per conversation and accepted offer. The PIN outcome and
-- any completion state are owned by the gated PIN workstream, not here.
CREATE TABLE hocalist.meetings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES hocalist.conversations(id) ON DELETE CASCADE,
  request_id uuid NOT NULL REFERENCES hocalist.requests(id),
  offer_id uuid NOT NULL REFERENCES hocalist.offers(id),
  buyer_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  seller_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed','accepted','reschedule_proposed','cancelled')),
  accepted_revision_id uuid,
  -- Exclusive start of the local day after the accepted meeting date, in the
  -- accepted IANA zone. Null until a schedule is accepted.
  meeting_expires_at timestamptz,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conversation_id, offer_id)
);

-- Immutable schedule history: every proposal keeps its local wall time, named
-- zone, server-resolved occurrence/offset/instant and place terms.
CREATE TABLE hocalist.meeting_schedule_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id uuid NOT NULL REFERENCES hocalist.meetings(id) ON DELETE CASCADE,
  sequence integer NOT NULL CHECK (sequence > 0),
  schedule_date date NOT NULL,
  schedule_time time NOT NULL,
  schedule_timezone text NOT NULL,
  schedule_occurrence text CHECK (schedule_occurrence IS NULL OR schedule_occurrence IN ('earlier','later')),
  schedule_offset_minutes integer NOT NULL,
  schedule_instant timestamptz NOT NULL,
  place_choice text NOT NULL CHECK (place_choice IN ('seller_business','buyer_location','specific_place')),
  place_label text,
  place_address text,
  place_id text,
  proposed_by_user_id uuid NOT NULL REFERENCES hocalist.profiles(id),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed','accepted','superseded','rejected','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  UNIQUE (meeting_id, sequence)
);

-- Idempotency receipts for meeting mutations: one row per (user, operation,
-- client key). A retry with the same payload replays the committed result; the
-- same key with a changed payload is refused.
CREATE TABLE hocalist.meeting_receipts (
  user_id uuid NOT NULL REFERENCES hocalist.profiles(id) ON DELETE CASCADE,
  operation text NOT NULL,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  request_hash text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation, idempotency_key)
);

CREATE INDEX meetings_participant_idx
  ON hocalist.meetings (buyer_user_id, updated_at DESC, id);
CREATE INDEX meetings_seller_idx
  ON hocalist.meetings (seller_user_id, updated_at DESC, id);
CREATE INDEX meeting_revisions_meeting_idx
  ON hocalist.meeting_schedule_revisions (meeting_id, sequence);

ALTER TABLE hocalist.meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.meeting_schedule_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.meeting_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.meetings, hocalist.meeting_schedule_revisions,
  hocalist.meeting_receipts
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Resolves one schedule input into a validated revision payload. Reuses the
-- marketplace normalizer so DST gaps/repeats and named zones stay one contract.
CREATE FUNCTION hocalist.meeting_normalize_schedule(p_input jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_norm jsonb;
BEGIN
  v_norm := hocalist.marketplace_normalize_offer(jsonb_build_object(
    'price_minor', 1,
    'currency_code', 'USD',
    'message', '',
    'image_media_ids', '[]'::jsonb,
    'schedule_date', p_input->>'schedule_date',
    'schedule_time', p_input->>'schedule_time',
    'schedule_timezone', p_input->>'schedule_timezone',
    'schedule_occurrence', p_input->>'schedule_occurrence',
    'place_choice', p_input->>'place_choice',
    'place_label', p_input->>'place_label',
    'place_address', p_input->>'place_address',
    'place_id', p_input->>'place_id'
  ));
  RETURN v_norm;
END; $$;

-- Serializes one meeting row and checks the caller participates in it with
-- current, role-appropriate access: the membership matching their side of the
-- meeting must still be active, the account must not be restricted or
-- disabled, and the conversation membership must not be revoked.
CREATE FUNCTION hocalist.meeting_assert_participant(
  p_meeting uuid,
  p_user uuid
) RETURNS hocalist.meetings
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_row hocalist.meetings%ROWTYPE;
  v_role text;
BEGIN
  SELECT * INTO v_row FROM hocalist.meetings WHERE id = p_meeting;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'meeting_not_found' USING ERRCODE='P0002';
  END IF;
  IF p_user IS NULL
     OR (p_user <> v_row.buyer_user_id AND p_user <> v_row.seller_user_id) THEN
    RAISE EXCEPTION 'meeting_access_denied' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  v_role := CASE WHEN p_user = v_row.buyer_user_id THEN 'buyer' ELSE 'seller' END;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships m
                 WHERE m.user_id = p_user AND m.role = v_role
                   AND m.status = 'active') THEN
    RAISE EXCEPTION 'role_not_active' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.conversation_members cm
                 WHERE cm.conversation_id = v_row.conversation_id
                   AND cm.user_id = p_user AND cm.revoked_at IS NULL) THEN
    RAISE EXCEPTION 'meeting_access_denied' USING ERRCODE='42501';
  END IF;
  RETURN v_row;
END; $$;

-- Same access policy for the proposing participant before a meeting row
-- exists. Mirrors the chat participant rules on the conversation.
CREATE FUNCTION hocalist.meeting_assert_conversation_member(
  p_conversation uuid,
  p_user uuid
) RETURNS hocalist.conversation_members
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_member hocalist.conversation_members%ROWTYPE;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_member FROM hocalist.conversation_members
    WHERE conversation_id = p_conversation AND user_id = p_user;
  IF NOT FOUND OR v_member.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'meeting_access_denied' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = p_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hocalist.memberships
                 WHERE id = v_member.profile_id AND user_id = p_user
                   AND role = v_member.role AND status = 'active') THEN
    RAISE EXCEPTION 'role_not_active' USING ERRCODE='42501';
  END IF;
  RETURN v_member;
END; $$;

-- Replays a committed meeting mutation, or returns null when the caller must
-- proceed. Identical retries serialize on (user, operation, key) so a
-- concurrent duplicate waits and then replays the committed result; the same
-- key with a changed payload is refused.
CREATE FUNCTION hocalist.meeting_receipt_begin(
  p_user uuid,
  p_operation text,
  p_key text,
  p_hash text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_receipt hocalist.meeting_receipts%ROWTYPE;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user::text || ':' || p_operation || ':' || p_key, 0));
  SELECT * INTO v_receipt FROM hocalist.meeting_receipts
    WHERE user_id = p_user AND operation = p_operation
      AND idempotency_key = p_key;
  IF FOUND THEN
    IF v_receipt.request_hash <> p_hash THEN
      RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001';
    END IF;
    RETURN v_receipt.result;
  END IF;
  RETURN NULL;
END; $$;

CREATE FUNCTION hocalist.meeting_receipt_store(
  p_user uuid,
  p_operation text,
  p_key text,
  p_hash text,
  p_result jsonb
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO hocalist.meeting_receipts(
    user_id, operation, idempotency_key, request_hash, result)
  VALUES (p_user, p_operation, p_key, p_hash, p_result)
  RETURNING result;
$$;

CREATE FUNCTION hocalist.meeting_revision_json(p_revision hocalist.meeting_schedule_revisions)
RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', p_revision.id,
    'meeting_id', p_revision.meeting_id,
    'sequence', p_revision.sequence,
    'schedule_date', p_revision.schedule_date,
    'schedule_time', p_revision.schedule_time,
    'schedule_timezone', p_revision.schedule_timezone,
    'schedule_occurrence', p_revision.schedule_occurrence,
    'schedule_offset_minutes', p_revision.schedule_offset_minutes,
    'schedule_instant', p_revision.schedule_instant,
    'place_choice', p_revision.place_choice,
    'place_label', p_revision.place_label,
    'place_address', p_revision.place_address,
    'place_id', p_revision.place_id,
    'proposed_by_user_id', p_revision.proposed_by_user_id,
    'status', p_revision.status,
    'created_at', p_revision.created_at,
    'resolved_at', p_revision.resolved_at
  );
$$;

-- Meeting JSON with the accepted schedule and the newest pending proposal.
CREATE FUNCTION hocalist.meeting_json(p_meeting uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', m.id,
    'conversation_id', m.conversation_id,
    'request_id', m.request_id,
    'offer_id', m.offer_id,
    'buyer_user_id', m.buyer_user_id,
    'seller_user_id', m.seller_user_id,
    'status', m.status,
    'accepted_revision_id', m.accepted_revision_id,
    'meeting_expires_at', m.meeting_expires_at,
    'revision', m.revision,
    'created_at', m.created_at,
    'updated_at', m.updated_at,
    -- Authorized summary tied to the offer revision the buyer accepted at
    -- selection time. It never substitutes a newer offer revision and stays
    -- null when the offer has no accepted revision.
    'offer_summary', (
      SELECT jsonb_build_object(
        'title', r.title,
        'price_minor', ar.price_minor,
        'currency_code', ar.currency_code,
        'revision_id', ar.id)
      FROM hocalist.offers o
      JOIN hocalist.offer_revisions ar ON ar.id = o.accepted_revision_id
      JOIN hocalist.requests r ON r.id = o.request_id
      WHERE o.id = m.offer_id
    ),
    'accepted_schedule', (
      SELECT hocalist.meeting_revision_json(r)
      FROM hocalist.meeting_schedule_revisions r
      WHERE r.id = m.accepted_revision_id
    ),
    'pending_schedule', (
      SELECT hocalist.meeting_revision_json(r)
      FROM hocalist.meeting_schedule_revisions r
      WHERE r.meeting_id = m.id AND r.status = 'proposed'
      ORDER BY r.sequence DESC LIMIT 1
    ),
    'revisions', coalesce((
      SELECT jsonb_agg(hocalist.meeting_revision_json(r) ORDER BY r.sequence)
      FROM hocalist.meeting_schedule_revisions r WHERE r.meeting_id = m.id
    ), '[]'::jsonb)
  )
  FROM hocalist.meetings m WHERE m.id = p_meeting;
$$;

-- ---------------------------------------------------------------------------
-- Client RPCs
-- ---------------------------------------------------------------------------

-- Proposes a meeting for a deal conversation whose offer is accepted. The
-- first call creates the meeting; a call after an initial proposal was
-- rejected appends another proposal to the same meeting, so history is kept
-- and one meeting stays per conversation/offer.
CREATE FUNCTION hocalist.meeting_propose(
  p_conversation uuid,
  p_input jsonb,
  p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_conv hocalist.conversations%ROWTYPE;
  v_offer hocalist.offers%ROWTYPE;
  v_meeting hocalist.meetings%ROWTYPE;
  v_norm jsonb;
  v_hash text;
  v_replay jsonb;
  v_meeting_id uuid;
  v_seq integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  IF p_conversation IS NULL OR p_input IS NULL
     OR jsonb_typeof(p_input) <> 'object' THEN
    RAISE EXCEPTION 'invalid_field: p_input' USING ERRCODE='22023';
  END IF;
  PERFORM hocalist.meeting_assert_conversation_member(p_conversation, v_user);
  SELECT * INTO v_conv FROM hocalist.conversations
    WHERE id = p_conversation AND origin = 'targeted_request' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'meeting_access_denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_offer FROM hocalist.offers
    WHERE id = v_conv.offer_id AND status = 'selected'
      AND conversation_id = p_conversation;
  IF NOT FOUND OR v_offer.accepted_revision_id IS NULL THEN
    RAISE EXCEPTION 'meeting_offer_not_selected' USING ERRCODE='P0001';
  END IF;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'conversation', p_conversation, 'input', p_input)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(
    v_user, 'meeting.propose', p_key, v_hash);
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  SELECT * INTO v_meeting FROM hocalist.meetings
    WHERE conversation_id = p_conversation AND offer_id = v_offer.id;
  IF FOUND THEN
    IF v_meeting.status = 'cancelled' THEN
      RAISE EXCEPTION 'meeting_cancelled' USING ERRCODE='P0001';
    END IF;
    IF v_meeting.accepted_revision_id IS NOT NULL
       OR v_meeting.status = 'accepted' THEN
      RAISE EXCEPTION 'meeting_already_exists' USING ERRCODE='P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM hocalist.meeting_schedule_revisions
               WHERE meeting_id = v_meeting.id AND status = 'proposed') THEN
      RAISE EXCEPTION 'meeting_reschedule_pending' USING ERRCODE='P0001';
    END IF;
    v_norm := hocalist.meeting_normalize_schedule(p_input);
    SELECT coalesce(max(sequence), 0) + 1 INTO v_seq
      FROM hocalist.meeting_schedule_revisions WHERE meeting_id = v_meeting.id;
    INSERT INTO hocalist.meeting_schedule_revisions(
      meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
      schedule_occurrence, schedule_offset_minutes, schedule_instant,
      place_choice, place_label, place_address, place_id, proposed_by_user_id)
    VALUES (
      v_meeting.id, v_seq,
      (v_norm->>'schedule_date')::date,
      (v_norm->>'schedule_time')::time,
      v_norm->>'schedule_timezone',
      v_norm->>'schedule_occurrence',
      (v_norm->>'schedule_offset_minutes')::integer,
      (v_norm->>'schedule_instant')::timestamptz,
      v_norm->>'place_choice',
      v_norm->>'place_label',
      v_norm->>'place_address',
      v_norm->>'place_id',
      v_user);
    UPDATE hocalist.meetings
      SET status = 'proposed', revision = revision + 1, updated_at = now()
      WHERE id = v_meeting.id;
    RETURN hocalist.meeting_receipt_store(
      v_user, 'meeting.propose', p_key, v_hash,
      hocalist.meeting_json(v_meeting.id));
  END IF;

  v_norm := hocalist.meeting_normalize_schedule(p_input);
  INSERT INTO hocalist.meetings(
    conversation_id, request_id, offer_id, buyer_user_id, seller_user_id)
  VALUES (
    p_conversation, v_offer.request_id, v_offer.id,
    v_offer.buyer_user_id, v_offer.seller_user_id)
  RETURNING id INTO v_meeting_id;

  INSERT INTO hocalist.meeting_schedule_revisions(
    meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
    schedule_occurrence, schedule_offset_minutes, schedule_instant,
    place_choice, place_label, place_address, place_id, proposed_by_user_id)
  VALUES (
    v_meeting_id, 1,
    (v_norm->>'schedule_date')::date,
    (v_norm->>'schedule_time')::time,
    v_norm->>'schedule_timezone',
    v_norm->>'schedule_occurrence',
    (v_norm->>'schedule_offset_minutes')::integer,
    (v_norm->>'schedule_instant')::timestamptz,
    v_norm->>'place_choice',
    v_norm->>'place_label',
    v_norm->>'place_address',
    v_norm->>'place_id',
    v_user);

  RETURN hocalist.meeting_receipt_store(
    v_user, 'meeting.propose', p_key, v_hash,
    hocalist.meeting_json(v_meeting_id));
END; $$;

-- Accepts or rejects the newest pending schedule. Accepting recomputes the
-- exclusive next-local-midnight expiry from the accepted local date/zone.
-- Rejecting the first proposal leaves the meeting open for another proposal.
CREATE FUNCTION hocalist.meeting_respond(
  p_meeting uuid,
  p_accept boolean,
  p_expected_revision bigint,
  p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row hocalist.meetings%ROWTYPE;
  v_rev hocalist.meeting_schedule_revisions%ROWTYPE;
  v_hash text;
  v_replay jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  IF p_accept IS NULL OR p_expected_revision IS NULL OR p_expected_revision < 1 THEN
    RAISE EXCEPTION 'invalid_field: p_expected_revision' USING ERRCODE='22023';
  END IF;
  v_row := hocalist.meeting_assert_participant(p_meeting, v_user);

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'meeting', p_meeting, 'accept', p_accept,
    'expected_revision', p_expected_revision)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(
    v_user, 'meeting.respond', p_key, v_hash);
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  SELECT * INTO v_row FROM hocalist.meetings WHERE id = p_meeting FOR UPDATE;
  IF v_row.revision <> p_expected_revision THEN
    RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
  END IF;
  IF v_row.status NOT IN ('proposed','reschedule_proposed') THEN
    RAISE EXCEPTION 'meeting_not_open' USING ERRCODE='P0001';
  END IF;
  SELECT * INTO v_rev FROM hocalist.meeting_schedule_revisions
    WHERE meeting_id = p_meeting AND status = 'proposed'
    ORDER BY sequence DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'meeting_not_open' USING ERRCODE='P0001';
  END IF;
  -- The proposer cannot accept their own proposal.
  IF v_rev.proposed_by_user_id = v_user THEN
    RAISE EXCEPTION 'meeting_self_accept' USING ERRCODE='P0001';
  END IF;

  IF p_accept THEN
    UPDATE hocalist.meeting_schedule_revisions
      SET status = 'superseded', resolved_at = now()
      WHERE meeting_id = p_meeting AND id <> v_rev.id
        AND status IN ('proposed','accepted');
    UPDATE hocalist.meeting_schedule_revisions
      SET status = 'accepted', resolved_at = now()
      WHERE id = v_rev.id;
    UPDATE hocalist.meetings
      SET status = 'accepted',
          accepted_revision_id = v_rev.id,
          meeting_expires_at = hocalist.marketplace_next_local_day_start(
            v_rev.schedule_date, v_rev.schedule_timezone),
          revision = revision + 1,
          updated_at = now()
      WHERE id = p_meeting;
  ELSE
    UPDATE hocalist.meeting_schedule_revisions
      SET status = 'rejected', resolved_at = now()
      WHERE id = v_rev.id;
    UPDATE hocalist.meetings
      SET status = CASE
            WHEN accepted_revision_id IS NULL THEN 'proposed'
            ELSE 'accepted'
          END,
          revision = revision + 1,
          updated_at = now()
      WHERE id = p_meeting;
  END IF;
  RETURN hocalist.meeting_receipt_store(
    v_user, 'meeting.respond', p_key, v_hash,
    hocalist.meeting_json(p_meeting));
END; $$;

-- Proposes a new schedule for an existing meeting. The accepted schedule stays
-- authoritative until the other participant accepts the reschedule.
CREATE FUNCTION hocalist.meeting_reschedule_propose(
  p_meeting uuid,
  p_input jsonb,
  p_expected_revision bigint,
  p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row hocalist.meetings%ROWTYPE;
  v_norm jsonb;
  v_hash text;
  v_replay jsonb;
  v_seq integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  IF p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
     OR p_expected_revision IS NULL OR p_expected_revision < 1 THEN
    RAISE EXCEPTION 'invalid_field: p_expected_revision' USING ERRCODE='22023';
  END IF;
  PERFORM hocalist.meeting_assert_participant(p_meeting, v_user);

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'meeting', p_meeting, 'input', p_input,
    'expected_revision', p_expected_revision)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(
    v_user, 'meeting.reschedule_propose', p_key, v_hash);
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  SELECT * INTO v_row FROM hocalist.meetings WHERE id = p_meeting FOR UPDATE;
  IF v_row.revision <> p_expected_revision THEN
    RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
  END IF;
  IF v_row.status NOT IN ('accepted','reschedule_proposed') THEN
    RAISE EXCEPTION 'meeting_not_accepted' USING ERRCODE='P0001';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hocalist.meeting_schedule_revisions
    WHERE meeting_id = p_meeting AND status = 'proposed'
  ) THEN
    RAISE EXCEPTION 'meeting_reschedule_pending' USING ERRCODE='P0001';
  END IF;

  v_norm := hocalist.meeting_normalize_schedule(p_input);
  SELECT coalesce(max(sequence), 0) + 1 INTO v_seq
  FROM hocalist.meeting_schedule_revisions WHERE meeting_id = p_meeting;
  INSERT INTO hocalist.meeting_schedule_revisions(
    meeting_id, sequence, schedule_date, schedule_time, schedule_timezone,
    schedule_occurrence, schedule_offset_minutes, schedule_instant,
    place_choice, place_label, place_address, place_id, proposed_by_user_id)
  VALUES (
    p_meeting, v_seq,
    (v_norm->>'schedule_date')::date,
    (v_norm->>'schedule_time')::time,
    v_norm->>'schedule_timezone',
    v_norm->>'schedule_occurrence',
    (v_norm->>'schedule_offset_minutes')::integer,
    (v_norm->>'schedule_instant')::timestamptz,
    v_norm->>'place_choice',
    v_norm->>'place_label',
    v_norm->>'place_address',
    v_norm->>'place_id',
    v_user);
  UPDATE hocalist.meetings
    SET status = 'reschedule_proposed',
        revision = revision + 1,
        updated_at = now()
    WHERE id = p_meeting;
  RETURN hocalist.meeting_receipt_store(
    v_user, 'meeting.reschedule_propose', p_key, v_hash,
    hocalist.meeting_json(p_meeting));
END; $$;

-- Cancels the meeting. Both participants may cancel; history is retained.
CREATE FUNCTION hocalist.meeting_cancel(
  p_meeting uuid,
  p_expected_revision bigint,
  p_key text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row hocalist.meetings%ROWTYPE;
  v_hash text;
  v_replay jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF p_key IS NULL OR length(btrim(p_key)) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid_field: p_key' USING ERRCODE='22023';
  END IF;
  IF p_expected_revision IS NULL OR p_expected_revision < 1 THEN
    RAISE EXCEPTION 'invalid_field: p_expected_revision' USING ERRCODE='22023';
  END IF;
  PERFORM hocalist.meeting_assert_participant(p_meeting, v_user);

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'meeting', p_meeting,
    'expected_revision', p_expected_revision)::text,'UTF8')),'hex');
  v_replay := hocalist.meeting_receipt_begin(
    v_user, 'meeting.cancel', p_key, v_hash);
  IF v_replay IS NOT NULL THEN
    RETURN v_replay;
  END IF;

  SELECT * INTO v_row FROM hocalist.meetings WHERE id = p_meeting FOR UPDATE;
  IF v_row.revision <> p_expected_revision THEN
    RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001';
  END IF;
  IF v_row.status = 'cancelled' THEN
    RETURN hocalist.meeting_receipt_store(
      v_user, 'meeting.cancel', p_key, v_hash,
      hocalist.meeting_json(p_meeting));
  END IF;
  UPDATE hocalist.meeting_schedule_revisions
    SET status = 'cancelled', resolved_at = now()
    WHERE meeting_id = p_meeting AND status = 'proposed';
  UPDATE hocalist.meetings
    SET status = 'cancelled',
        meeting_expires_at = NULL,
        revision = revision + 1,
        updated_at = now()
    WHERE id = p_meeting;
  RETURN hocalist.meeting_receipt_store(
    v_user, 'meeting.cancel', p_key, v_hash,
    hocalist.meeting_json(p_meeting));
END; $$;

-- One meeting by id for a participant.
CREATE FUNCTION hocalist.meeting_detail(p_meeting uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  PERFORM hocalist.meeting_assert_participant(p_meeting, v_user);
  RETURN hocalist.meeting_json(p_meeting);
END; $$;

-- Participant meetings, newest first, optional status filter.
CREATE FUNCTION hocalist.meeting_list(
  p_status text,
  p_limit integer,
  p_cursor text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := auth.uid();
  v_limit integer;
  v_updated timestamptz;
  v_id uuid;
  v_items jsonb;
  v_next text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
             WHERE user_id = v_user AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'account_restricted' USING ERRCODE='42501';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN
     ('proposed','accepted','reschedule_proposed','cancelled') THEN
    RAISE EXCEPTION 'invalid_field: p_status' USING ERRCODE='22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'invalid_field: p_limit' USING ERRCODE='22023';
  END IF;
  v_limit := p_limit;
  IF p_cursor IS NOT NULL AND btrim(p_cursor) <> '' THEN
    IF p_cursor !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]{8,}\|[0-9a-f-]{36}$' THEN
      RAISE EXCEPTION 'invalid_field: p_cursor' USING ERRCODE='22023';
    END IF;
    BEGIN
      v_updated := split_part(p_cursor, '|', 1)::timestamptz;
      v_id := split_part(p_cursor, '|', 2)::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_field: p_cursor' USING ERRCODE='22023';
    END;
  END IF;

  SELECT coalesce(jsonb_agg(row_json ORDER BY updated_at DESC, id DESC), '[]'::jsonb)
    INTO v_items
  FROM (
    SELECT m.updated_at, m.id, hocalist.meeting_json(m.id) AS row_json
    FROM hocalist.meetings m
    WHERE (m.buyer_user_id = v_user OR m.seller_user_id = v_user)
      AND EXISTS (
        SELECT 1 FROM hocalist.conversation_members cm
        WHERE cm.conversation_id = m.conversation_id
          AND cm.user_id = v_user AND cm.revoked_at IS NULL)
      AND EXISTS (
        SELECT 1 FROM hocalist.memberships ms
        WHERE ms.user_id = v_user
          AND ms.role = CASE WHEN m.buyer_user_id = v_user
                             THEN 'buyer' ELSE 'seller' END
          AND ms.status = 'active')
      AND (p_status IS NULL OR m.status = p_status)
      AND (v_updated IS NULL OR (m.updated_at, m.id) < (v_updated, v_id))
    ORDER BY m.updated_at DESC, m.id DESC
    LIMIT v_limit + 1
  ) page;

  IF jsonb_array_length(v_items) > v_limit THEN
    v_next := (v_items->(v_limit - 1)->>'updated_at') || '|' ||
              (v_items->(v_limit - 1)->>'id');
    v_items := (SELECT coalesce(jsonb_agg(value), '[]'::jsonb)
                FROM jsonb_array_elements(v_items) WITH ORDINALITY AS t(value, ord)
                WHERE ord <= v_limit);
  END IF;

  RETURN jsonb_build_object('items', v_items, 'next_cursor', v_next);
END; $$;

-- ---------------------------------------------------------------------------
-- Grants and post-apply verification
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION hocalist.meeting_normalize_schedule(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_assert_participant(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_assert_conversation_member(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_receipt_begin(uuid,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_receipt_store(uuid,text,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_json(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_revision_json(hocalist.meeting_schedule_revisions)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_propose(uuid,jsonb,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_respond(uuid,boolean,bigint,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_cancel(uuid,bigint,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_detail(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.meeting_list(text,integer,text)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION hocalist.meeting_propose(uuid,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.meeting_respond(uuid,boolean,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.meeting_reschedule_propose(uuid,jsonb,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.meeting_cancel(uuid,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.meeting_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION hocalist.meeting_list(text,integer,text) TO authenticated;

DO $hocalist_meeting_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
  v_client_functions constant text[] := ARRAY[
    'meeting_propose(uuid,jsonb,text)','meeting_respond(uuid,boolean,bigint,text)',
    'meeting_reschedule_propose(uuid,jsonb,bigint,text)','meeting_cancel(uuid,bigint,text)',
    'meeting_detail(uuid)','meeting_list(text,integer,text)'];
  v_internal_functions constant text[] := ARRAY[
    'meeting_normalize_schedule(jsonb)','meeting_assert_participant(uuid,uuid)',
    'meeting_assert_conversation_member(uuid,uuid)',
    'meeting_receipt_begin(uuid,text,text,text)',
    'meeting_receipt_store(uuid,text,text,text,jsonb)',
    'meeting_json(uuid)','meeting_revision_json(hocalist.meeting_schedule_revisions)'];
  v_fn text;
  v_table text;
  v_columns text[];
  v_expected_meetings constant text[] := ARRAY[
    'id:uuid','conversation_id:uuid','request_id:uuid','offer_id:uuid',
    'buyer_user_id:uuid','seller_user_id:uuid','status:text',
    'accepted_revision_id:uuid','meeting_expires_at:timestamp with time zone',
    'revision:bigint','created_at:timestamp with time zone',
    'updated_at:timestamp with time zone'];
  v_expected_receipts constant text[] := ARRAY[
    'user_id:uuid','operation:text','idempotency_key:text',
    'request_hash:text','result:jsonb','created_at:timestamp with time zone'];
BEGIN
  FOREACH v_table IN ARRAY ARRAY['meetings','meeting_schedule_revisions','meeting_receipts'] LOOP
    IF to_regclass('hocalist.' || v_table) IS NULL THEN
      v_issues := array_append(v_issues, 'missing meeting table: ' || v_table);
    ELSIF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('hocalist.' || v_table)::regclass) THEN
      v_issues := array_append(v_issues, 'row level security disabled: ' || v_table);
    END IF;
  END LOOP;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.meetings'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_meetings THEN
    v_issues := array_append(v_issues, 'meetings columns differ from the reviewed shape');
  END IF;
  SELECT array_agg(attname || ':' || format_type(atttypid, atttypmod) ORDER BY attnum)
    INTO v_columns
  FROM pg_attribute
  WHERE attrelid='hocalist.meeting_receipts'::regclass AND attnum>0 AND NOT attisdropped;
  IF v_columns IS DISTINCT FROM v_expected_receipts THEN
    v_issues := array_append(v_issues, 'meeting_receipts columns differ from the reviewed shape');
  END IF;
  FOREACH v_fn IN ARRAY v_client_functions LOOP
    IF NOT has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'meeting function grants are wrong: ' || v_fn);
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY v_internal_functions LOOP
    IF has_function_privilege('authenticated', 'hocalist.' || v_fn, 'EXECUTE')
       OR has_function_privilege('anon', 'hocalist.' || v_fn, 'EXECUTE') THEN
      v_issues := array_append(v_issues, 'internal meeting function is executable: ' || v_fn);
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='hocalist' AND table_name='meetings'
      AND column_name IN ('pin','pin_hash','pin_attempts')
  ) THEN
    v_issues := array_append(v_issues, 'PIN columns must not exist in the meeting foundation');
  END IF;
  IF NOT has_function_privilege('authenticated','hocalist.marketplace_timezones()','EXECUTE')
     OR NOT has_function_privilege('authenticated','hocalist.account_command(text,text,jsonb)','EXECUTE') THEN
    v_issues := array_append(v_issues, 'deployed account/marketplace grants changed');
  END IF;
  IF coalesce(array_length(v_issues,1),0) > 0 THEN
    RAISE EXCEPTION 'hocalist meeting post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_meeting_postapply$;
COMMIT;

-- Prepared for explicit owner approval. Existing verified owner only.
-- Does not create/change Auth users, passwords or Postaneur profiles.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';
DO $owner_admin$
DECLARE
  v_owner constant uuid := '91d18569-1e56-464b-8503-215d9584647a';
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users WHERE id = v_owner
      AND lower(email) = 'coachnonan@gmail.com'
      AND email_confirmed_at IS NOT NULL
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Verified owner identity changed; aborting'; END IF;
  IF EXISTS (SELECT 1 FROM hocalist.memberships
    WHERE user_id=v_owner AND status IN ('restricted','disabled')) THEN
    RAISE EXCEPTION 'Owner identity is restricted; review required';
  END IF;
  INSERT INTO hocalist.profiles(id) VALUES(v_owner) ON CONFLICT(id) DO NOTHING;
  INSERT INTO hocalist.platform_admins(user_id) VALUES(v_owner) ON CONFLICT(user_id) DO NOTHING;
  IF NOT hocalist.marketplace_is_admin(v_owner) THEN
    RAISE EXCEPTION 'Owner admin verification failed';
  END IF;
END $owner_admin$;
COMMIT;

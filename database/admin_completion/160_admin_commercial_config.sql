-- Additive administrator-only read of the admin-managed commercial
-- configuration (160, draft).
--
-- Exposes exactly the two reviewed configuration sources an authorized admin
-- edits through the existing `credit_admin_command`:
--   * `credit_deposit_options` including retired rows and revisions, so an
--     editor can carry the current revision and show an honest empty state;
--   * the singleton `reward_policy`, or JSON null when it has never been
--     configured (never an invented default).
--
-- Read-only: this file seeds nothing, activates nothing and reprices no batch.
-- Historical batches keep their immutable rate snapshot regardless of edits.
--
-- Not an instruction to apply to a live project. Generate a guarded rollout
-- bundle and obtain coordinating review before applying.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $admin_commercial_config_guard$
BEGIN
  IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL
     OR to_regprocedure('hocalist.credit_admin_command(text,text,jsonb)') IS NULL
     OR to_regclass('hocalist.credit_deposit_options') IS NULL
     OR to_regclass('hocalist.reward_policy') IS NULL THEN
    RAISE EXCEPTION 'Admin commercial configuration requires the credit settlement contract';
  END IF;
  IF to_regprocedure('hocalist.admin_commercial_config()') IS NOT NULL THEN
    RAISE EXCEPTION 'Admin commercial configuration read already exists; review before replacement';
  END IF;
END
$admin_commercial_config_guard$;

CREATE FUNCTION hocalist.admin_commercial_config()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_options jsonb;
  v_policy jsonb;
BEGIN
  PERFORM hocalist.marketplace_assert_admin(auth.uid());
  -- Every option, active or retired, with its revision. No fee rate is
  -- inferred or defaulted anywhere in this projection.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', o.id,
      'amount_minor', o.amount_minor,
      'initial_fee_minor', o.initial_fee_minor,
      'winning_total_minor', o.winning_total_minor,
      'rate_version', o.rate_version,
      'active', o.active,
      'sort_order', o.sort_order,
      'revision', o.revision,
      'updated_at', o.updated_at
    ) ORDER BY o.sort_order, o.amount_minor, o.id), '[]'::jsonb)
    INTO v_options
    FROM hocalist.credit_deposit_options o;

  SELECT jsonb_build_object(
      'normal_minor', p.normal_minor,
      'late_minor', p.late_minor,
      'late_window_hours', p.late_window_hours,
      'rule_version', p.rule_version,
      'revision', p.revision,
      'updated_at', p.updated_at)
    INTO v_policy
    FROM hocalist.reward_policy p WHERE p.singleton;

  RETURN jsonb_build_object(
    'deposit_options', v_options,
    'reward_policy', coalesce(v_policy, 'null'::jsonb));
END; $$;

REVOKE ALL ON FUNCTION hocalist.admin_commercial_config()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION hocalist.admin_commercial_config() TO authenticated;

DO $hocalist_admin_commercial_config_postapply$
DECLARE
  v_issues text[] := ARRAY[]::text[];
BEGIN
  IF NOT has_function_privilege('authenticated','hocalist.admin_commercial_config()','EXECUTE')
     OR has_function_privilege('anon','hocalist.admin_commercial_config()','EXECUTE')
     OR has_function_privilege('service_role','hocalist.admin_commercial_config()','EXECUTE') THEN
    v_issues := array_append(v_issues, 'admin commercial configuration grants are wrong');
  END IF;
  IF has_table_privilege('authenticated','hocalist.credit_deposit_options','SELECT')
     OR has_table_privilege('authenticated','hocalist.reward_policy','SELECT')
     OR has_table_privilege('anon','hocalist.credit_deposit_options','SELECT')
     OR has_table_privilege('service_role','hocalist.credit_deposit_options','SELECT') THEN
    v_issues := array_append(v_issues, 'private commercial configuration became client-readable');
  END IF;
  IF coalesce(array_length(v_issues, 1), 0) > 0 THEN
    RAISE EXCEPTION 'hocalist admin commercial configuration post-apply verification failed: %',
      array_to_string(v_issues, ' | ');
  END IF;
END
$hocalist_admin_commercial_config_postapply$;
COMMIT;

-- Private support cases. No automatic account penalties or financial action.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF to_regprocedure('hocalist.marketplace_assert_admin(uuid)') IS NULL THEN RAISE EXCEPTION 'Marketplace admin prerequisite missing'; END IF;
 IF to_regclass('hocalist.support_cases') IS NOT NULL THEN RAISE EXCEPTION 'Support already installed'; END IF;
END; $guard$;
CREATE TABLE hocalist.support_reasons(code text PRIMARY KEY CHECK(code ~ '^[a-z_]{1,40}$'),label text NOT NULL CHECK(length(btrim(label)) BETWEEN 1 AND 100),active boolean NOT NULL DEFAULT true,sort_order integer NOT NULL DEFAULT 0,revision bigint NOT NULL DEFAULT 1 CHECK(revision>0));
INSERT INTO hocalist.support_reasons(code,label,sort_order) VALUES ('general','General support',0),('safety','Unsafe interaction',1),('account','Account access',2),('deal','Request, offer or meeting',3);
CREATE TABLE hocalist.support_cases(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),reporter_id uuid NOT NULL REFERENCES auth.users(id),
 reason_code text NOT NULL REFERENCES hocalist.support_reasons(code),
 body text NOT NULL CHECK(length(btrim(body)) BETWEEN 10 AND 4000),
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','in_review','resolved')),
 response text CHECK(response IS NULL OR length(response) BETWEEN 1 AND 4000),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX support_cases_owner_order ON hocalist.support_cases(reporter_id,id);
CREATE TABLE hocalist.support_case_events(case_id uuid NOT NULL REFERENCES hocalist.support_cases(id),revision bigint NOT NULL,actor_id uuid NOT NULL REFERENCES auth.users(id),status text NOT NULL,response text,created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(case_id,revision));
CREATE TABLE hocalist.support_receipts(user_id uuid NOT NULL REFERENCES auth.users(id),operation text NOT NULL,key text NOT NULL,hash text NOT NULL,result jsonb NOT NULL,PRIMARY KEY(user_id,operation,key));
ALTER TABLE hocalist.support_reasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.support_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.support_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE hocalist.support_case_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON hocalist.support_reasons,hocalist.support_cases,hocalist.support_receipts,hocalist.support_case_events FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION hocalist.support_assert_user() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid(); BEGIN
 -- Restricted users must retain an appeals/support channel.
 IF u IS NULL OR NOT EXISTS(SELECT 1 FROM hocalist.memberships WHERE user_id=u) THEN RAISE EXCEPTION 'support_access_denied' USING ERRCODE='42501'; END IF;
 RETURN u;
END; $$;
CREATE FUNCTION hocalist.support_reasons(p_include_retired boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_include_retired THEN PERFORM hocalist.marketplace_assert_admin(auth.uid()); ELSE PERFORM hocalist.support_assert_user(); END IF;
 RETURN jsonb_build_object('items',coalesce((SELECT jsonb_agg(jsonb_build_object('code',code,'label',label,'active',active,'sort_order',sort_order,'revision',revision) ORDER BY sort_order,code) FROM hocalist.support_reasons WHERE active OR p_include_retired),'[]'::jsonb));
END; $$;
CREATE FUNCTION hocalist.support_list(p_limit integer DEFAULT 30,p_cursor uuid DEFAULT NULL,p_admin boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();rows jsonb;next_id uuid; BEGIN
 IF p_admin THEN PERFORM hocalist.marketplace_assert_admin(u); ELSE PERFORM hocalist.support_assert_user(); END IF;
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_admin IS NULL THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
 WITH found AS (
 SELECT c.*,r.label AS reason FROM hocalist.support_cases c JOIN hocalist.support_reasons r ON r.code=c.reason_code
 WHERE (p_admin OR c.reporter_id=u) AND (p_cursor IS NULL OR c.id>p_cursor) ORDER BY c.id LIMIT p_limit+1),
 page AS(SELECT * FROM found ORDER BY id LIMIT p_limit)
 SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'reason',reason,'body',body,'status',status,'response',response,'revision',revision,'created_at',created_at,'updated_at',updated_at) ORDER BY id) FROM page),'[]'::jsonb),
 CASE WHEN (SELECT count(*) FROM found)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END INTO rows,next_id;
 RETURN jsonb_build_object('items',rows,'next_cursor',next_id);
END; $$;
CREATE FUNCTION hocalist.support_command(p_operation text,p_key text,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid:=auth.uid();h text;receipt hocalist.support_receipts%ROWTYPE;c hocalist.support_cases%ROWTYPE;result jsonb; BEGIN
 IF p_operation IN ('review','reason.save') THEN PERFORM hocalist.marketplace_assert_admin(u); ELSE PERFORM hocalist.support_assert_user(); END IF;
 IF p_operation IS NULL OR p_operation NOT IN('create','review','reason.save') OR p_key IS NULL OR length(p_key) NOT BETWEEN 1 AND 200 OR jsonb_typeof(p_input) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023'; END IF;
 h:=md5(p_input::text);
 PERFORM pg_advisory_xact_lock(hashtextextended(u::text||'support'||p_operation||p_key,0));
 SELECT * INTO receipt FROM hocalist.support_receipts WHERE user_id=u AND operation=p_operation AND key=p_key;
 IF FOUND THEN IF receipt.hash<>h THEN RAISE EXCEPTION 'idempotency_conflict' USING ERRCODE='P0001'; END IF; RETURN receipt.result; END IF;
 IF p_operation='create' THEN
  IF p_input - ARRAY['reason_code','body'] <> '{}'::jsonb OR jsonb_typeof(p_input->'body') IS DISTINCT FROM 'string' OR length(btrim(p_input->>'body')) NOT BETWEEN 10 AND 4000
  OR NOT EXISTS(SELECT 1 FROM hocalist.support_reasons WHERE code=p_input->>'reason_code' AND active) THEN RAISE EXCEPTION 'invalid_report' USING ERRCODE='22023'; END IF;
  INSERT INTO hocalist.support_cases(reporter_id,reason_code,body) VALUES(u,p_input->>'reason_code',btrim(p_input->>'body')) RETURNING * INTO c;
  result:=jsonb_build_object('id',c.id,'revision',c.revision,'status',c.status);
 ELSIF p_operation='review' THEN
  IF p_input - ARRAY['case_id','expected_revision','status','response'] <> '{}'::jsonb
   OR coalesce(p_input->>'status','') NOT IN('open','in_review','resolved')
   OR jsonb_typeof(p_input->'response') IS DISTINCT FROM 'string' OR length(btrim(p_input->>'response')) NOT BETWEEN 1 AND 4000 THEN RAISE EXCEPTION 'invalid_review' USING ERRCODE='22023'; END IF;
  UPDATE hocalist.support_cases SET status=p_input->>'status',response=btrim(p_input->>'response'),revision=revision+1,updated_at=now()
  WHERE id=(p_input->>'case_id')::uuid AND revision=(p_input->>'expected_revision')::bigint RETURNING * INTO c;
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  result:=jsonb_build_object('id',c.id,'revision',c.revision,'status',c.status);
 ELSE
  IF p_input - ARRAY['code','label','active','sort_order','expected_revision'] <> '{}'::jsonb OR jsonb_typeof(p_input->'active') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid_reason' USING ERRCODE='22023'; END IF;
  INSERT INTO hocalist.support_reasons(code,label,active,sort_order) VALUES(p_input->>'code',btrim(p_input->>'label'),(p_input->>'active')::boolean,coalesce((p_input->>'sort_order')::integer,0))
  ON CONFLICT(code) DO UPDATE SET label=excluded.label,active=excluded.active,sort_order=excluded.sort_order,revision=hocalist.support_reasons.revision+1
  WHERE hocalist.support_reasons.revision=(p_input->>'expected_revision')::bigint;
  IF NOT FOUND THEN RAISE EXCEPTION 'revision_conflict' USING ERRCODE='P0001'; END IF;
  result:=jsonb_build_object('code',p_input->>'code');
 END IF;
 IF p_operation IN('create','review') THEN
  INSERT INTO hocalist.support_case_events(case_id,revision,actor_id,status,response) VALUES(c.id,c.revision,u,c.status,c.response);
 END IF;
 INSERT INTO hocalist.support_receipts VALUES(u,p_operation,p_key,h,result);
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION hocalist.support_assert_user(),hocalist.support_reasons(boolean),hocalist.support_list(integer,uuid,boolean),hocalist.support_command(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.support_reasons(boolean),hocalist.support_list(integer,uuid,boolean),hocalist.support_command(text,text,jsonb) TO authenticated;
COMMIT;

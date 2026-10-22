-- Category questions for requests and Store listings. Existing role, revision,
-- fee and receipt paths remain canonical; only answer validation/storage is added.
BEGIN;
ALTER TABLE hocalist.requests ADD COLUMN IF NOT EXISTS category_answers jsonb NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(category_answers)='array');
ALTER TABLE hocalist.store_listings ADD COLUMN IF NOT EXISTS category_answers jsonb NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(category_answers)='array');

CREATE OR REPLACE FUNCTION hocalist.catalogue_answer_input(p_snapshot jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce(jsonb_object_agg(a->>'group_id',a->'option_ids'),'{}'::jsonb)
 FROM jsonb_array_elements(coalesce(p_snapshot,'[]'::jsonb)) a;
$$;
CREATE OR REPLACE FUNCTION hocalist.catalogue_validate_answers(p_category uuid,p_answers jsonb,p_required boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE g hocalist.catalogue_option_groups%ROWTYPE; k text; v jsonb; result jsonb:='[]'; labels jsonb; n integer;
BEGIN
 IF jsonb_typeof(p_answers) IS DISTINCT FROM 'object' OR octet_length(p_answers::text)>16000 THEN
  RAISE EXCEPTION 'invalid_field: category_answers' USING ERRCODE='22023'; END IF;
 IF (SELECT count(*) FROM jsonb_object_keys(p_answers))>40 THEN RAISE EXCEPTION 'invalid_field: category_answers' USING ERRCODE='22023'; END IF;
 FOR k,v IN SELECT key,value FROM jsonb_each(p_answers) LOOP
  SELECT * INTO g FROM hocalist.catalogue_option_groups WHERE id::text=k AND category_id=p_category AND status='active';
  IF NOT FOUND OR jsonb_typeof(v) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'invalid_field: category_answers' USING ERRCODE='22023'; END IF;
  n:=jsonb_array_length(v);
  IF n>20 OR (g.selection_mode='single' AND n>1) OR EXISTS(SELECT 1 FROM jsonb_array_elements(v) e WHERE jsonb_typeof(e)<>'string') THEN
   RAISE EXCEPTION 'invalid_field: category_answers' USING ERRCODE='22023'; END IF;
  SELECT jsonb_agg(o.label ORDER BY o.sort_order,o.id) INTO labels FROM hocalist.catalogue_options o WHERE o.group_id=g.id AND o.status='active' AND v ? o.id::text;
  IF coalesce(jsonb_array_length(labels),0)<>n THEN RAISE EXCEPTION 'invalid_field: category_answers' USING ERRCODE='22023'; END IF;
  IF n>0 THEN result:=result||jsonb_build_array(jsonb_build_object('group_id',g.id,'label',g.label,'option_ids',v,'labels',labels)); END IF;
 END LOOP;
 IF p_required AND EXISTS(SELECT 1 FROM hocalist.catalogue_option_groups q WHERE q.category_id=p_category AND q.status='active' AND q.is_required AND coalesce(jsonb_array_length(p_answers->q.id::text),0)=0) THEN
  RAISE EXCEPTION 'required_category_answers' USING ERRCODE='22023'; END IF;
 RETURN result;
END; $$;

DO $$ BEGIN
 IF to_regprocedure('hocalist.marketplace_normalize_request_before_questions(jsonb)') IS NULL THEN ALTER FUNCTION hocalist.marketplace_normalize_request(jsonb) RENAME TO marketplace_normalize_request_before_questions; END IF;
 IF to_regprocedure('hocalist.marketplace_normalize_listing_before_questions(jsonb)') IS NULL THEN ALTER FUNCTION hocalist.marketplace_normalize_listing(jsonb) RENAME TO marketplace_normalize_listing_before_questions; END IF;
END $$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_normalize_request(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE n jsonb; answers jsonb;
BEGIN
 n:=hocalist.marketplace_normalize_request_before_questions(p_input-'category_answers');
 answers:=p_input->'category_answers';
 IF answers IS NULL AND p_input ? 'request_id' THEN SELECT hocalist.catalogue_answer_input(r.category_answers) INTO answers FROM hocalist.requests r WHERE r.id::text=p_input->>'request_id' AND r.buyer_user_id=auth.uid() AND r.category_id IS NOT DISTINCT FROM (n->>'category_id')::uuid; END IF;
 RETURN n||jsonb_build_object('category_answers',hocalist.catalogue_validate_answers((n->>'category_id')::uuid,coalesce(answers,'{}'),true));
END $$;
CREATE OR REPLACE FUNCTION hocalist.marketplace_normalize_listing(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE n jsonb; answers jsonb; required boolean;
BEGIN
 n:=hocalist.marketplace_normalize_listing_before_questions(p_input-'category_answers');
 answers:=p_input->'category_answers'; required:=n->>'publish_intent'='publish';
 IF p_input ? 'listing_id' THEN
  SELECT coalesce(required,false) OR l.status='active',coalesce(answers,CASE WHEN l.category_id=(n->>'category_id')::uuid THEN hocalist.catalogue_answer_input(l.category_answers) ELSE '{}'::jsonb END) INTO required,answers FROM hocalist.store_listings l WHERE l.id::text=p_input->>'listing_id' AND l.seller_user_id=auth.uid();
 END IF;
 RETURN n||jsonb_build_object('category_answers',hocalist.catalogue_validate_answers((n->>'category_id')::uuid,coalesce(answers,'{}'),coalesce(required,false)));
END $$;

-- Extend current deployed definitions rather than replacing fee/meeting repairs
-- with a historical command body. Refuse unexpected prerequisite drift.
DO $$
DECLARE d text; original text; signature text; target text; added text;
BEGIN
 signature:='hocalist.marketplace_command(text,text,jsonb)'; d:=pg_get_functiondef(signature::regprocedure); original:=d;
 IF strpos(d,'-- category_answers_v1')=0 THEN
  IF strpos(d,'v_result := hocalist.marketplace_request_json(v_id);')=0 OR strpos(d,'v_result := hocalist.marketplace_listing_json(v_id);')=0 OR strpos(d,'IF (p_input->>''publish'')::boolean THEN')=0 THEN RAISE EXCEPTION 'category command prerequisite drift'; END IF;
  d:=replace(d,'v_result := hocalist.marketplace_request_json(v_id);',$q$-- category_answers_v1
    IF p_operation IN ('request.create','request.update') THEN
      UPDATE hocalist.requests SET category_answers=v_norm->'category_answers' WHERE id=v_id AND buyer_user_id=v_user;
    END IF;
    v_result := hocalist.marketplace_request_json(v_id);$q$);
  d:=replace(d,'v_result := hocalist.marketplace_listing_json(v_id);',$q$IF p_operation IN ('store.create','store.update') THEN
      UPDATE hocalist.store_listings SET category_answers=v_norm->'category_answers' WHERE id=v_id AND seller_user_id=v_user;
    ELSIF p_operation='store.duplicate' THEN
      UPDATE hocalist.store_listings SET category_answers=(SELECT category_answers FROM hocalist.store_listings WHERE id=(p_input->>'listing_id')::uuid AND seller_user_id=v_user) WHERE id=v_id AND seller_user_id=v_user;
    END IF;
    v_result := hocalist.marketplace_listing_json(v_id);$q$);
  d:=replace(d,'IF (p_input->>''publish'')::boolean THEN',$q$IF (p_input->>'publish')::boolean THEN
      PERFORM hocalist.catalogue_validate_answers(v_listing.category_id,hocalist.catalogue_answer_input(v_listing.category_answers),true);$q$);
  EXECUTE d;
 END IF;
 FOR signature,target,added IN SELECT * FROM (VALUES
 ('hocalist.marketplace_request_json(uuid)', '''category_id'', r.category_id,','''category_id'', r.category_id, ''category_answers'', r.category_answers,'),
 ('hocalist.marketplace_lead_json(uuid)', '''category_id'', r.category_id,','''category_id'', r.category_id, ''category_answers'', r.category_answers,'),
 ('hocalist.marketplace_listing_json(uuid)', '''category_id'', l.category_id,','''category_id'', l.category_id, ''category_answers'', l.category_answers,'),
 ('hocalist.marketplace_public_listing_json(uuid)', '''category_id'', l.category_id,','''category_id'', l.category_id, ''category_answers'', l.category_answers,')
 ) AS patches(signature,target,added) LOOP
  d:=pg_get_functiondef(signature::regprocedure);
  IF strpos(d,'''category_answers''')=0 THEN
   IF strpos(d,target)=0 THEN RAISE EXCEPTION 'category projection prerequisite drift: %',signature; END IF;
   EXECUTE replace(d,target,added);
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION hocalist.catalogue_answer_input(jsonb),hocalist.catalogue_validate_answers(uuid,jsonb,boolean),hocalist.marketplace_normalize_request(jsonb),hocalist.marketplace_normalize_listing(jsonb),hocalist.marketplace_normalize_request_before_questions(jsonb),hocalist.marketplace_normalize_listing_before_questions(jsonb) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

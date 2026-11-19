BEGIN;
ALTER TABLE hocalist.requests DROP CONSTRAINT request_coordinates_valid;
ALTER TABLE hocalist.requests ADD CONSTRAINT request_coordinates_valid CHECK (
 (latitude IS NULL AND longitude IS NULL) OR
 (latitude IS NOT NULL AND longitude IS NOT NULL AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180));
DO $patch$ DECLARE definition text; signature text; old text := 'IF v_use_home OR jsonb_typeof(p_input->''latitude'')'; BEGIN
 signature:=CASE WHEN to_regprocedure('hocalist.marketplace_normalize_request_before_questions(jsonb)') IS NOT NULL THEN 'hocalist.marketplace_normalize_request_before_questions(jsonb)' ELSE 'hocalist.marketplace_normalize_request(jsonb)' END;
 definition:=pg_get_functiondef(signature::regprocedure);
 IF position('CASE WHEN v_use_home THEN NULL ELSE v_city END' IN definition)=0 THEN RAISE EXCEPTION 'Home area snapshot prerequisite drift'; END IF;
 definition:=replace(definition,old,'IF jsonb_typeof(p_input->''latitude'')');
 definition:=replace(definition,'''city'', CASE WHEN v_use_home THEN NULL ELSE v_city END',
 '''city'', CASE WHEN v_use_home THEN coalesce(v_city,(SELECT city FROM hocalist.profile_contacts WHERE user_id=auth.uid())) ELSE v_city END');
 definition:=replace(definition,'''region'', CASE WHEN v_use_home THEN NULL ELSE v_region END',
 '''region'', CASE WHEN v_use_home THEN coalesce(v_region,(SELECT region FROM hocalist.profile_contacts WHERE user_id=auth.uid())) ELSE v_region END');
 EXECUTE definition;
END $patch$;
NOTIFY pgrst,'reload schema';
COMMIT;

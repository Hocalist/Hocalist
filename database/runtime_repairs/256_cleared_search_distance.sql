-- Distance display may use the saved business origin without reapplying a cleared search radius.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $patch$
DECLARE proc record; definition text; anchor text; replacement text;
BEGIN
 FOR proc IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='hocalist' AND p.proname IN ('marketplace_discovery_leads','marketplace_recommended_leads')
 LOOP
  definition:=pg_get_functiondef(proc.oid);
  IF position('-- saved-business-distance-fallback' IN definition)>0 THEN CONTINUE; END IF;
  anchor:=CASE WHEN proc.proname='marketplace_discovery_leads'
    THEN 'v_radius := coalesce(p_radius_miles, v_origin.radius_miles);'
    ELSE 'v_radius := v_origin.radius_miles;' END;
  IF position(anchor IN definition)=0 OR position('hocalist.discovery_distance_miles' IN definition)=0 THEN
    RAISE EXCEPTION 'Distance fallback prerequisite drift: %',proc.proname;
  END IF;
  replacement:=anchor||E'\n  -- saved-business-distance-fallback\n  IF v_origin.latitude IS NULL AND v_origin.longitude IS NULL\n     AND nullif(btrim(v_origin.area_label), '''') IS NULL THEN\n    SELECT a.latitude, a.longitude INTO v_origin.latitude, v_origin.longitude\n      FROM hocalist.seller_business_addresses a WHERE a.user_id=v_user;\n    v_radius := '||CASE WHEN proc.proname='marketplace_discovery_leads' THEN 'p_radius_miles' ELSE 'NULL' END||E';\n  END IF;';
  EXECUTE replace(definition,anchor,replacement);
 END LOOP;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='hocalist' AND p.proname IN ('marketplace_discovery_leads','marketplace_recommended_leads'))<>2 THEN
   RAISE EXCEPTION 'Expected two discovery functions';
 END IF;
END $patch$;
COMMIT;

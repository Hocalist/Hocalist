-- Keep the authenticated market projection compatible with LocationEntry.
BEGIN;
DO $$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('hocalist.marketplace_locations(text,boolean)'::regprocedure);
 IF strpos(d,'''created_at''')=0 AND strpos(d,'''updated_at''')=0 THEN
  IF strpos(d,'''revision'', l.revision)')=0 THEN
   RAISE EXCEPTION 'market location projection prerequisite drift';
  END IF;
  EXECUTE replace(d,'''revision'', l.revision)',
    '''revision'', l.revision, ''created_at'', l.created_at, ''updated_at'', l.updated_at)');
 ELSIF strpos(d,'''created_at''')=0 OR strpos(d,'''updated_at''')=0 THEN
  RAISE EXCEPTION 'market location projection partially updated';
 END IF;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

-- Service gateway only. Existing Postaneur policies/objects are preserved.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF to_regclass('hocalist.media_images') IS NULL THEN RAISE EXCEPTION 'media foundation missing'; END IF;
 IF EXISTS(SELECT 1 FROM storage.buckets WHERE id='hocalist-images') THEN RAISE EXCEPTION 'bucket already exists: inspect before changing'; END IF;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='storage.objects'::regclass AND polname='hocalist_images_gateway_only') THEN RAISE EXCEPTION 'policy already exists'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='storage.objects'::regclass) THEN RAISE EXCEPTION 'storage RLS missing'; END IF;
END $$;
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 VALUES('hocalist-images','hocalist-images',false,4194304,ARRAY['image/jpeg']);
-- Restrictive policy intersects any pre-existing broad permissive policies;
-- it only prevents direct client access to this new Hocalist bucket.
CREATE POLICY hocalist_images_gateway_only ON storage.objects AS RESTRICTIVE
 FOR ALL TO anon,authenticated
 USING(bucket_id IS DISTINCT FROM 'hocalist-images')
 WITH CHECK(bucket_id IS DISTINCT FROM 'hocalist-images');
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='hocalist-images' AND NOT public AND file_size_limit=4194304 AND allowed_mime_types=ARRAY['image/jpeg']) THEN RAISE EXCEPTION 'bucket verification failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='storage.objects'::regclass AND polname='hocalist_images_gateway_only' AND NOT polpermissive AND polcmd='*') THEN RAISE EXCEPTION 'bucket policy verification failed'; END IF;
END $$;
COMMIT;

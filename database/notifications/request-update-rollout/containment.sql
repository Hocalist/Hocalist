BEGIN;
-- Contains the producer only: the trigger stops firing while the extended
-- kind constraint, functions and the optional leads topic remain installed.
DROP TRIGGER IF EXISTS notification_request_update ON hocalist.requests;
COMMIT;

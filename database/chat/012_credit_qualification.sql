-- Additive qualification hook: a committed message insert checks whether both
-- parties have now sent a qualifying message in a targeted-request negotiation,
-- which charges the initial HocaCredit fee once. The credit helper is resolved
-- dynamically so the chat foundation keeps working without the commercial
-- module applied.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

DO $guard$ BEGIN
  IF to_regclass('hocalist.conversation_messages') IS NULL THEN
    RAISE EXCEPTION 'chat foundation 010 prerequisite missing';
  END IF;
  IF to_regclass('hocalist.conversation_credit_hook') IS NOT NULL THEN
    RAISE EXCEPTION 'credit qualification hook already installed';
  END IF;
END; $guard$;

CREATE TABLE hocalist.conversation_credit_hook (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  installed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO hocalist.conversation_credit_hook(singleton) VALUES (true);
ALTER TABLE hocalist.conversation_credit_hook ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION hocalist.chat_message_credit_qualify() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF to_regprocedure('hocalist.credit_qualify_conversation(uuid)') IS NOT NULL THEN
    PERFORM hocalist.credit_qualify_conversation(NEW.conversation_id);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER chat_message_credit_qualify
  AFTER INSERT ON hocalist.conversation_messages
  FOR EACH ROW EXECUTE FUNCTION hocalist.chat_message_credit_qualify();

REVOKE ALL ON TABLE hocalist.conversation_credit_hook FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION hocalist.chat_message_credit_qualify() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;

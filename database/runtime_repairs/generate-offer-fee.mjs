import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const read = path => readFile(new URL(path,import.meta.url),'utf8');
const hash = value => createHash('md5').update(value.replaceAll('\r\n','\n')).digest('hex');
const baseline = (await read('../commercial/092_credit_settlement.sql')).replaceAll('\r\n','\n');
const extract = name => {
  const start = baseline.indexOf(`CREATE FUNCTION hocalist.${name}(`);
  const end = baseline.indexOf('END $$;',start)+7;
  if(start<0 || end<7) throw Error('missing baseline function');
  return baseline.slice(start,end);
};
const body = sql => sql.slice(sql.indexOf('AS $$')+5,sql.lastIndexOf('$$;'));
const oldAuthorize = extract('credit_authorize_target');
const oldQualify = extract('credit_qualify_conversation');
const authorize = oldAuthorize.replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION')
  .replace('  SELECT * INTO t FROM hocalist.credit_targets WHERE id=v_id;',
    `  -- Reserve and debit atomically inside the successful offer submission.
  -- The existing target/ledger lock makes command retries charge at most once.
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=v_id;
  IF t.status='reserved' THEN
    PERFORM hocalist.credit_settle_internal(v_id,'initial');
  END IF;
  SELECT * INTO t FROM hocalist.credit_targets WHERE id=v_id;`)
  .replace("'status','reserved'","'status',t.status");
const qualify = `CREATE OR REPLACE FUNCTION hocalist.credit_qualify_conversation(p_conversation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  -- Compatibility boundary only. Messages never debit an initial offer fee.
  -- Historical reservations are not charged retroactively by this migration.
  RETURN jsonb_build_object('status','not_chargeable');
END $$;`;
const functions = [
  ['credit_authorize_target(uuid,uuid,uuid)',oldAuthorize,authorize],
  ['credit_qualify_conversation(uuid)',oldQualify,qualify],
];
function guard(correctedOnly=false) {
 return functions.map(([signature,oldSql,newSql])=>`DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.${signature}')
   AND md5(replace(prosrc,E'\\r\\n',E'\\n')) IN (${(correctedOnly?[hash(body(newSql))]:[hash(body(oldSql)),hash(body(newSql))]).map(x=>`'${x}'`).join(',')})
   AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN
   RAISE EXCEPTION 'Offer fee definition drift: ${signature}'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure('hocalist.${signature}') AND a.privilege_type='EXECUTE'
   AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Offer fee helper grants drift: ${signature}'; END IF;
END $guard$;`).join('\n');
}
const triggerGuard=`DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.conversation_messages'::regclass
   AND tgname='chat_message_credit_qualify' AND NOT tgisinternal
   AND tgfoid IS DISTINCT FROM to_regprocedure('hocalist.chat_message_credit_qualify()')) THEN
   RAISE EXCEPTION 'Offer fee trigger drift'; END IF;
END $guard$;`;
await writeFile(new URL('./offer-fee-preflight.sql',import.meta.url),`BEGIN READ ONLY;\n${guard()}\n${triggerGuard}\nCOMMIT;\n`);
const verify = `${guard(true)}
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='hocalist.conversation_messages'::regclass
  AND tgname='chat_message_credit_qualify' AND NOT tgisinternal) THEN
  RAISE EXCEPTION 'Message fee trigger remains'; END IF;
END $guard$;`;
await writeFile(new URL('./207_offer_submission_fee.sql',import.meta.url),`-- Initial fee is charged by successful offer submission, never by chat.
-- No historical target, balance, deposit rate or purchase total is rewritten.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
${guard()}
${triggerGuard}
${authorize}
${qualify}
DROP TRIGGER IF EXISTS chat_message_credit_qualify ON hocalist.conversation_messages;
${verify}
COMMIT;
`);
await writeFile(new URL('./offer-fee-verify.sql',import.meta.url),`BEGIN READ ONLY;\n${verify}\nCOMMIT;\n`);

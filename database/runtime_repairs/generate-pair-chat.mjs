import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const hash=s=>createHash('md5').update(s.replaceAll('\r\n','\n')).digest('hex');
function extract(source,name){
 const start=source.search(new RegExp(`CREATE (?:OR REPLACE )?FUNCTION hocalist\\.${name}\\(`));
 const end=source.indexOf('END; $$;',start);
 const alt=source.indexOf('END $$;',start);
 const stop=end<0?alt+7:alt<0?end+8:Math.min(end+8,alt+7);
 if(start<0||stop<start)throw Error(name);
 return source.slice(start,stop);
}
const body=s=>s.slice(s.indexOf('AS $$')+5,s.lastIndexOf('$$;'));
const chat=extract((await read('../chat/010_chat_foundation.sql')).replaceAll('\r\n','\n'),'chat_open_internal');
const meeting=extract((await read('./192_confirmed_meeting_coordinates.sql')).replaceAll('\r\n','\n'),'meeting_propose');
const pair=chat.replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION').replace(
 '  SELECT c.id INTO v_id FROM hocalist.conversations c',
 `  -- Serialize all origins for the same exact participant set.
  PERFORM pg_advisory_xact_lock(hashtextextended((SELECT string_agg(e->>'user_id',',' ORDER BY e->>'user_id') FROM jsonb_array_elements(p_participants) e),209));
  SELECT c.id INTO v_id FROM hocalist.conversations c`).replace(
 `  WHERE c.origin = p_origin
    AND c.request_id IS NOT DISTINCT FROM p_request
    AND c.offer_id IS NOT DISTINCT FROM p_offer
    AND c.listing_id IS NOT DISTINCT FROM p_listing
    AND c.discovery_topic_id IS NOT DISTINCT FROM p_topic`,
 `  WHERE c.status='open'
    AND jsonb_array_length(p_participants)=2
    AND (SELECT count(*) FROM jsonb_array_elements(p_participants) e WHERE e->>'role'='buyer')=1
    AND (SELECT count(*) FROM jsonb_array_elements(p_participants) e WHERE e->>'role'='seller')=1
    AND NOT EXISTS(SELECT 1 FROM hocalist.conversation_members m WHERE m.conversation_id=c.id
      AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_participants) e WHERE (e->>'user_id')::uuid=m.user_id AND (e->>'profile_id')::uuid=m.profile_id AND e->>'role'=m.role))`).replace('  LIMIT 1;','  ORDER BY c.created_at,c.id LIMIT 1;');
const propose=meeting.replace("    WHERE id = p_conversation AND origin = 'targeted_request' FOR UPDATE;","    WHERE id = p_conversation FOR UPDATE;").replace(
 `    WHERE id = v_conv.offer_id AND status = 'selected'
      AND conversation_id = p_conversation;`,
 `    WHERE status='selected' AND conversation_id=p_conversation
      AND id=CASE WHEN p_input ? 'offer_id' THEN (p_input->>'offer_id')::uuid
       WHEN (SELECT count(*) FROM hocalist.offers WHERE conversation_id=p_conversation AND status='selected')=1
       THEN (SELECT id FROM hocalist.offers WHERE conversation_id=p_conversation AND status='selected' LIMIT 1) END;`).replace(
 `  v_hash := encode(sha256`,
 `  IF NOT EXISTS(SELECT 1 FROM hocalist.requests WHERE id=v_offer.request_id AND purchase_offer_id=v_offer.id) THEN
    RAISE EXCEPTION 'confirm_seller_before_meeting' USING ERRCODE='P0001';
  END IF;
  v_hash := encode(sha256`);
if(pair===chat||!propose.includes('confirm_seller_before_meeting'))throw Error('replacement failed');
const specs=[['chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)',chat,pair],['meeting_propose(uuid,jsonb,text)',meeting,propose]];
const guard=(final=false)=>`DO $guard$ BEGIN\n${specs.map(([sig,old,next])=>` IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.${sig}') AND md5(replace(prosrc,E'\\r\\n',E'\\n')) IN (${(final?[next]:[old,next]).map(x=>`'${hash(body(x))}'`).join(',')}) AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat definition drift: ${sig}'; END IF;`).join('\n')}
 IF EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=to_regprocedure('hocalist.chat_open_internal(text,uuid,uuid,uuid,uuid,jsonb)') AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Pair chat helper grants drift'; END IF;
 IF to_regprocedure('hocalist.chat_deals(uuid)') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('hocalist.chat_deals(uuid)') AND md5(replace(prosrc,E'\\r\\n',E'\\n'))='${hash(body(offers))}' AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Pair chat read drift'; END IF;
 ${final?`IF to_regprocedure('hocalist.chat_deals(uuid)') IS NULL OR NOT has_function_privilege('authenticated','hocalist.chat_deals(uuid)','EXECUTE') OR has_function_privilege('anon','hocalist.chat_deals(uuid)','EXECUTE') OR has_function_privilege('service_role','hocalist.chat_deals(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Pair chat read grants drift'; END IF;`:''}
END $guard$;\n`;
const offers=`CREATE OR REPLACE FUNCTION hocalist.chat_deals(p_conversation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM hocalist.meeting_assert_conversation_member(p_conversation,auth.uid());
 RETURN jsonb_build_object('items',coalesce((SELECT jsonb_agg(hocalist.marketplace_offer_json(o.id) ORDER BY o.created_at,o.id)
   FROM hocalist.offers o WHERE o.conversation_id=p_conversation AND o.status='selected'),'[]'::jsonb),'next_cursor',null);
END $$;
REVOKE ALL ON FUNCTION hocalist.chat_deals(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION hocalist.chat_deals(uuid) TO authenticated;
`;
await writeFile(new URL('./209_pair_conversations.sql',import.meta.url),`-- Reuse participant threads; offers and fees remain separate deals.\n-- Existing messages/history are preserved; legacy threads are not destructively merged.\nBEGIN;\nSET LOCAL lock_timeout='5s';\n${guard()}${pair}\n${propose}\n${offers}${guard(true)}NOTIFY pgrst,'reload schema';\nCOMMIT;\n`);
await writeFile(new URL('./pair-chat-preflight.sql',import.meta.url),`BEGIN READ ONLY;\n${guard()}COMMIT;\n`);
await writeFile(new URL('./pair-chat-verify.sql',import.meta.url),`BEGIN READ ONLY;\n${guard(true)}COMMIT;\n`);

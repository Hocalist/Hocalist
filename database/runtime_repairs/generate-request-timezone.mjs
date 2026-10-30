import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const hash=s=>createHash('md5').update(s.replace(/\r/g,'')).digest('hex');
const extract=(sql,name)=>{
 const match=sql.match(new RegExp(`CREATE (?:OR REPLACE )?FUNCTION hocalist\\.${name}\\([\\s\\S]*?AS \\$\\$([\\s\\S]*?)\\$\\$;`));
 if(!match)throw Error(`Missing ${name}`);
 return {definition:match[0].replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION'),body:match[1]};
};
const specs=[
 ['../marketplace/021_request_coordinates.sql','marketplace_normalize_request','jsonb'],
 ['../marketplace/023_multi_negotiation.sql','marketplace_request_json','uuid'],
 ['./192_confirmed_meeting_coordinates.sql','marketplace_command','text,text,jsonb'],
 ['../marketplace/023_multi_negotiation.sql','marketplace_lead_json','uuid'],
 ['../discovery_completion/140_discovery_leads.sql','discovery_lead_json','uuid,double precision,integer,jsonb'],
];
const patches=[];
for(const[file,name,args]of specs){
 let {definition,body}=extract(await read(file),name);
 if(name==='marketplace_lead_json'){
  const old="'published_at', r.created_at)";
  const value="'published_at', r.created_at, 'verified_purchase_count', (SELECT count(*) FROM hocalist.sale_confirmations s WHERE s.buyer_user_id=r.buyer_user_id))";
  definition=definition.replace(old,value);body=body.replace(old,value);
 }
 const before=body,changes=[];
 let intermediate;
 const replace=(old,value)=>{if(!body.includes(old))throw Error(`Missing patch ${name}: ${old}`);changes.push([old,value]);body=body.replace(old,()=>value);};
 if(name==='marketplace_normalize_request'){
  replace("'latitude','longitude'];","'latitude','longitude','location_timezone'];");
  replace('BEGIN',`BEGIN
  IF p_input->>'location_timezone' IS NOT NULL AND NOT hocalist.marketplace_valid_timezone(p_input->>'location_timezone') THEN
    RAISE EXCEPTION 'invalid_field: location_timezone' USING ERRCODE='22023';
  END IF;`);
  replace("'latitude', p_input->'latitude',", "'location_timezone', p_input->>'location_timezone', 'latitude', p_input->'latitude',");
 }else if(name==='marketplace_command'){
  replace('country_code, latitude, longitude)','country_code, latitude, longitude, location_timezone)');
  replace("(v_norm->>'longitude')::double precision)","(v_norm->>'longitude')::double precision, v_norm->>'location_timezone')");
  replace("latitude = (v_norm->>'latitude')::double precision,","location_timezone = v_norm->>'location_timezone',\n      latitude = (v_norm->>'latitude')::double precision,");
 }else if(name==='marketplace_request_json'){
  replace("'use_home_address', r.use_home_address,","'use_home_address', r.use_home_address, 'timezone_id', r.location_timezone,");
 }else{
  replace("'request_revision', r.revision,","'location_timezone', r.location_timezone, 'request_revision', r.revision,");
  intermediate=hash(body);
  replace('coalesce(rp.area_label, r.city, r.region)', "CASE WHEN r.use_home_address THEN rp.area_label ELSE coalesce(nullif(btrim(r.city),''),nullif(btrim(r.region),''),rp.area_label) END");
 }
 patches.push({name,signature:`hocalist.${name}(${args})`,before:hash(before),after:hash(body),definition:definition.replace(before,()=>body),changes,intermediate});
}
const guard=phase=>`DO $guard$ BEGIN\n${patches.map(p=>` IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('${p.signature}') AND md5(replace(prosrc,chr(13),'')) IN ('${p.after}'${phase==='before'?`, '${p.before}'${p.intermediate?`, '${p.intermediate}'`:''}`:''}) AND prosecdef AND proconfig=ARRAY['search_path=""']) THEN RAISE EXCEPTION 'Request timezone drift: ${p.name}'; END IF;`).join('\n')}\nEND $guard$;`;
await writeFile(new URL('./210_request_location_timezone.sql',import.meta.url),`-- Preserve buyer-confirmed timezones; seller projections remain area-only.
BEGIN;
SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='30s';
${guard('before')}
ALTER TABLE hocalist.requests ADD COLUMN IF NOT EXISTS location_timezone text
 CHECK(location_timezone IS NULL OR hocalist.marketplace_valid_timezone(location_timezone));
${patches.map(p=>p.definition).join('\n')}
${guard('after')}
NOTIFY pgrst, 'reload schema';
COMMIT;
`);
await writeFile(new URL('./request-timezone-preflight.sql',import.meta.url),guard('before'));
await writeFile(new URL('./request-timezone-verify.sql',import.meta.url),guard('after'));
const quote=s=>`'${s.replaceAll("'","''")}'`;
await writeFile(new URL('./request-timezone-browser.sql',import.meta.url),`BEGIN;
${guard('before')}
ALTER TABLE hocalist.requests ADD COLUMN IF NOT EXISTS location_timezone text CHECK(location_timezone IS NULL OR hocalist.marketplace_valid_timezone(location_timezone));
${patches.map(p=>`DO $patch$ DECLARE original text; body text; definition text; BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO original,definition FROM pg_proc WHERE oid=${quote(p.signature)}::regprocedure;
 IF md5(replace(original,chr(13),''))=${quote(p.after)} THEN RETURN; END IF;
 body:=original;
 ${p.intermediate?`IF md5(replace(original,chr(13),''))=${quote(p.intermediate)} THEN body:=replace(body,${quote(p.changes.at(-1)[0])},${quote(p.changes.at(-1)[1])}); ELSE`:''}
 ${p.changes.map(([a,b])=>`body:=replace(body,${quote(a)},${quote(b)});`).join('\n ')}
 ${p.intermediate?'END IF;':''}
 EXECUTE replace(definition,original,body);
END $patch$;`).join('\n')}
${guard('after')}
NOTIFY pgrst,'reload schema'; COMMIT;`);

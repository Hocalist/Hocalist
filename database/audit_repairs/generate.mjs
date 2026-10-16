import {readFile,writeFile} from 'node:fs/promises';
import {createCommercialDb} from '../commercial_completion/tests/fixture.mjs';
const source=await readFile(new URL('200_audit_reads.sql',import.meta.url),'utf8');
const guard=source.slice(source.indexOf('DO $guard$'),source.indexOf('END $guard$;')+'END $guard$;'.length);
await writeFile(new URL('preflight.sql',import.meta.url),'-- Read-only prerequisite checks; no user records are changed.\n'+guard+'\n');
const db=await createCommercialDb();
try {
 await db.exec(source);
 const signatures=['marketplace_request(uuid)','marketplace_offer_json(uuid)','marketplace_lead_json(uuid)','commercial_deal_summary()','public_store(uuid)'];
 const rows=[];
 for(const signature of signatures){
  const {rows:[row]}=await db.query("SELECT md5(replace(prosrc,chr(13),'')) AS hash FROM pg_proc WHERE oid=to_regprocedure($1)",['hocalist.'+signature]);
  rows.push(`    ('hocalist.${signature}','${row.hash}')`);
 }
 const verify=`-- Read-only exact-body and access verification.\nDO $verify$\nDECLARE item record;\nBEGIN\n FOR item IN SELECT * FROM (VALUES\n${rows.join(',\n')}\n ) AS functions(signature,hash) LOOP\n  IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid=to_regprocedure(item.signature)) IS DISTINCT FROM item.hash THEN\n   RAISE EXCEPTION 'Audit repair verification drift: %',item.signature;\n  END IF;\n END LOOP;\n IF has_function_privilege('anon','hocalist.commercial_deal_summary()','EXECUTE') OR\n    NOT has_function_privilege('authenticated','hocalist.commercial_deal_summary()','EXECUTE') OR\n    NOT has_function_privilege('anon','hocalist.public_store(uuid)','EXECUTE') OR\n    has_function_privilege('anon','hocalist.marketplace_request(uuid)','EXECUTE') OR\n    has_function_privilege('authenticated','hocalist.marketplace_offer_json(uuid)','EXECUTE') OR\n    has_function_privilege('anon','hocalist.marketplace_lead_json(uuid)','EXECUTE') THEN\n  RAISE EXCEPTION 'Audit repair grant drift';\n END IF;\nEND $verify$;\n`;
 await db.exec(verify);
 await writeFile(new URL('verify.sql',import.meta.url),verify);
} finally {await db.close();}

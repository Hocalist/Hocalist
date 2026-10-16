import {createPlacesAuthVerifier} from '../hocalist-places/auth.ts';
import {createCallIceBrowserHandler} from './handler.ts';
const project='https://icqwbzswokoulatomgql.supabase.co';
Deno.serve(req=>{
 const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
 const verify=createPlacesAuthVerifier(project,service);
 return createCallIceBrowserHandler({
  enabled:Deno.env.get('HOCALIST_CALLS_ENABLED')==='true'&&Deno.env.get('SUPABASE_URL')===project&&!!service,
  secret:Deno.env.get('HOCALIST_TURN_SECRET')??'',urls:(Deno.env.get('HOCALIST_TURN_URLS')??'').split(',').filter(Boolean),
  authenticate:async authorization=>{const user=await verify(authorization);return 'userId' in user?user.userId:null;},
  callState:async(authorization,id)=>{
   const response=await fetch(`${project}/rest/v1/rpc/call_command`,{method:'POST',headers:{apikey:service,Authorization:authorization,'Content-Type':'application/json','Content-Profile':'hocalist'},body:JSON.stringify({p_action:'poll',p_input:{call_id:id}}),signal:AbortSignal.timeout(10000)});
   if(!response.ok){await response.body?.cancel();return null;}
   return (await response.json()).call?.state??null;
  },
 })(req);
});

import {placesPreflight, withPlacesCors} from '../hocalist-places/cors.ts';
type Dependencies={enabled:boolean;secret:string;urls:string[];authenticate:(authorization:string)=>Promise<string|null>;callState:(authorization:string,id:string)=>Promise<string|null>;now?:()=>number};
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export function createCallIceHandler(d:Dependencies){return async(req:Request)=>{
 if(req.method!=='POST')return json({error:'method_not_allowed'},405);
 if(!d.enabled||!d.secret||!d.urls.length||d.urls.some(u=>!/^turns?:[a-z0-9.-]+:\d+(\?transport=(udp|tcp))?$/i.test(u)))return json({error:'calls_unconfigured'},404);
 try{
  const authorization=req.headers.get('authorization')??'';
  const user=await d.authenticate(authorization);
  if(!user)return json({error:'unauthorized'},401);
  const reader=req.body?.getReader();if(!reader)return json({error:'invalid_input'},400);
  let total=0;const chunks:Uint8Array[]=[];
  while(true){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>4096){await reader.cancel();return json({error:'invalid_input'},413);}chunks.push(value);}
  const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return json({error:'invalid_input'},400);}
  if(!body||typeof body.call_id!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(body.call_id))return json({error:'invalid_input'},400);
  if(await d.callState(authorization,body.call_id)!=='accepted')return json({error:'call_finished'},409);
  const expiry=Math.floor((d.now?.()??Date.now())/1000)+600;
  const username=`${expiry}:${user}`;
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(d.secret),{name:'HMAC',hash:'SHA-1'},false,['sign']);
  const signature=new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(username)));
  return json({iceServers:[{urls:d.urls,username,credential:btoa(String.fromCharCode(...signature))}],expires_at:expiry});
 }catch{return json({error:'unavailable'},503);}
};}

export function createCallIceBrowserHandler(d:Dependencies) {
 const handler=createCallIceHandler(d);
 return async(req:Request)=>req.method==='OPTIONS'
  ? placesPreflight(req)
  : withPlacesCors(req,await handler(req));
}

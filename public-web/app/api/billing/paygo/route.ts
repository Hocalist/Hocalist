import {NextResponse} from 'next/server';
import {cookies} from 'next/headers';
import {guardFailure,guardMutation,readBoundedJson} from '../../../lib/website-guard';
import {providerRedirect,refreshCookieOptions,sessionCookieOptions,uuidHint} from '../../../lib/website-rules';
import {callBillingFunction,callRpc,type FunctionResult,type RpcResult,REFRESH_COOKIE,SESSION_COOKIE,siteConfig,withSessionRefresh} from '../../../lib/website-session';

async function handle(request:Request,operation:'status'|'begin'|'confirm'|'revoke'|'verify'|'refresh'|'retry',payload:Record<string,unknown>={}) {
 // Keep setup out of the released product until collection and recovery are ready.
 if(process.env.HOCALIST_PAYGO_TEST_ENABLED!=='true')return NextResponse.json({state:'unavailable'},{status:503});
 const config=siteConfig();if(!config)return NextResponse.json({state:'unavailable'},{status:503});
 const store=await cookies(),token=store.get(SESSION_COOKIE)?.value??'',refresh=store.get(REFRESH_COOKIE)?.value??'';
 if(!token&&!refresh)return NextResponse.json({state:'signed_out'},{status:401});
 const {result,refreshed}=await withSessionRefresh<RpcResult|FunctionResult>(config,token,refresh,
  async value=>operation==='status'||operation==='revoke'
   ? operation==='status'?await (async()=>{const sync=await callBillingFunction(config,value,'hocalist-paygo-setup',{operation:'sync'});return sync.ok?callRpc(config,value,'paygo_payment_status',{}):sync;})():callRpc(config,value,'paygo_payment_revoke',{})
   :callBillingFunction(config,value,['verify','refresh','retry'].includes(operation)?'hocalist-paygo-recovery':'hocalist-paygo-setup',{operation,...payload}),
  value=>!value.ok&&value.status===401);
 const respond=(body:Record<string,unknown>,status=200)=>{
  const response=NextResponse.json(body,{status,headers:{'Cache-Control':'no-store'}});
  if(refreshed){const isProduction=process.env.NODE_ENV==='production';
   response.cookies.set(SESSION_COOKIE,refreshed.accessToken,sessionCookieOptions({expiresIn:refreshed.expiresIn,isProduction}));
   response.cookies.set(REFRESH_COOKIE,refreshed.refreshToken,refreshCookieOptions({isProduction}));}
  return response;
 };
 if(!result.ok)return respond({state:result.status===401?'signed_out':'error',code:result.code,message:result.code==='setup_expired'?'That card setup has expired. Start again to save your card.':'Payment permission could not be updated. Try again shortly.'},result.status===401?401:409);
 const data=(result.data??{}) as Record<string,unknown>;
 if(operation==='begin'){
  if(data.state==='needs_confirmation'&&uuidHint(data.setup_id))return respond({state:'needs_confirmation',setup_id:data.setup_id});
  const url=providerRedirect(data.url,'checkout.stripe.com');
  if(!url||!uuidHint(data.setup_id))return respond({state:'error',message:'The payment setup link could not be verified.'},502);
  return respond({state:'ready',url,setup_id:data.setup_id});
 }
 if(operation==='status')return respond({state:'ready',authorised:data.authorised===true,charges:Array.isArray(data.charges)?data.charges:[]});
 if(operation==='revoke')return respond({state:'revoked'});
 if(operation==='verify'){
  if(data.state==='needs_refresh')return respond({state:'needs_refresh'});
  if(data.state!=='requires_action'||typeof data.client_secret!=='string'||!/^pi_[A-Za-z0-9]+_secret_[A-Za-z0-9]+$/.test(data.client_secret)||typeof data.publishable_key!=='string'||!/^pk_test_[A-Za-z0-9]+$/.test(data.publishable_key))return respond({state:'error'},502);
  return respond({state:'requires_action',client_secret:data.client_secret,publishable_key:data.publishable_key});
 }
 if(operation==='refresh'||operation==='retry')return respond({state:['succeeded','pending','requires_action','requires_payment_method','processing','canceled','queued','waiting_for_initial','review'].includes(String(data.state))?data.state:'error'});
 return respond({state:['authorised','pending','expired'].includes(String(data.state))?data.state:'error'});
}
export async function GET(request:Request){return handle(request,'status');}
export async function POST(request:Request){
 const guard=guardMutation(request,{policy:'session',maxBytes:1024});if(!guard.ok)return guardFailure(guard);
 const parsed=await readBoundedJson(request,1024);if(!parsed.ok)return NextResponse.json({state:'invalid'},{status:parsed.status});
 const body=parsed.body as Record<string,unknown>;
 if(!body||typeof body!=='object'||Array.isArray(body))return NextResponse.json({state:'invalid'},{status:400});
 const keys=Object.keys(body).sort().join(',');
 if(body.operation==='begin'&&keys==='consent_version,idempotency_key,operation'&&body.consent_version==='paygo-v1'&&uuidHint(body.idempotency_key))
  return handle(request,'begin',{consent_version:'paygo-v1',idempotency_key:body.idempotency_key});
 if(body.operation==='confirm'&&keys==='operation,setup_id'&&uuidHint(body.setup_id))return handle(request,'confirm',{setup_id:body.setup_id});
 if(body.operation==='revoke'&&keys==='operation')return handle(request,'revoke');
 if(['verify','refresh','retry'].includes(String(body.operation))&&keys==='charge_id,operation'&&uuidHint(body.charge_id))return handle(request,body.operation as 'verify'|'refresh'|'retry',{charge_id:body.charge_id});
 return NextResponse.json({state:'invalid'},{status:400});
}

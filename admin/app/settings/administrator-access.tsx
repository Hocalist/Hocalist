"use client";
import { useEffect, useRef, useState } from 'react';
import { adminRpc } from '../lib/admin-client';
import {WorkspaceDrawer} from '../workspace-drawer';
type Administrator = { user_id:string; email:string; manager:boolean; mfa_ready:boolean; granted_at:string };
type AccessHistory = { id:string; action:string; target_email:string|null; created_at:string };
type Access = { can_manage:boolean; items:Administrator[]; history:AccessHistory[] };
export function AdministratorAccess() {
 const [data,setData]=useState<Access|null>(null), [email,setEmail]=useState(''), [busy,setBusy]=useState(false), [message,setMessage]=useState('');
 const [intent,setIntent]=useState<{action:'grant'|'revoke';email:string;key:string}|null>(null);
 const [editorOpen,setEditorOpen]=useState(false);
 const version=useRef(0), gate=useRef(false);
 async function load() {
  const current=++version.current;
  const result=await adminRpc('admin_access_list',{});
  if(current!==version.current)return;
  if(!result.ok){setData(null);setMessage('Verify your authenticator to view administrator access. Only authorised access managers can make changes.');return;}
  const value=result.data as Access;
  if(!value || typeof value.can_manage!=='boolean' || !Array.isArray(value.items) || !Array.isArray(value.history) || value.items.some(x=>typeof x.email!=='string'||typeof x.user_id!=='string'||typeof x.manager!=='boolean'||typeof x.mfa_ready!=='boolean')){
   setData(null);setMessage('Administrator access could not be loaded safely. Please retry.');return;
  }
  setData(value);setMessage('');
 }
 useEffect(()=>{void load();return()=>{++version.current;};},[]);
 function prepare(action:'grant'|'revoke',target:string){if(busy||!data?.can_manage)return;setIntent({action,email:target.trim(),key:crypto.randomUUID()});setMessage('');}
 async function confirm() {
  if(!intent||gate.current)return;gate.current=true;setBusy(true);
  try {
   const result=await adminRpc('admin_access_command',{p_action:intent.action,p_email:intent.email,p_key:intent.key});
   if(!result.ok){setMessage(result.message || 'Access could not be changed. Check the verified account and retry.');return;}
   setIntent(null);setEditorOpen(false);setEmail('');await load();setMessage('Administrator access updated.');
  }finally{gate.current=false;setBusy(false);}
 }
 return <section className="panel administrator-access">
  <div className="admin-access-heading"><div><h2>Administrators</h2><p>Manage who can access Hocalist operations. New administrators must verify their email and set up an authenticator.</p></div><button className="text-action" type="button" disabled={busy} onClick={()=>void load()}>Reload</button></div>
  {data?.can_manage&&<button className="primary" disabled={busy} onClick={()=>setEditorOpen(true)}>Add administrator</button>}<WorkspaceDrawer title={intent?"Confirm administrator access":"Add administrator"} open={editorOpen||!!intent} locked={busy} onClose={()=>{setEditorOpen(false);setIntent(null)}}>{data?.can_manage && !intent && <form className="admin-access-add" onSubmit={e=>{e.preventDefault();prepare('grant',email);}}><label>Existing Hocalist account email<input type="email" autoComplete="off" maxLength={254} required value={email} onChange={e=>setEmail(e.target.value)} disabled={busy}/></label><button className="primary" disabled={busy} type="submit">Add administrator</button></form>}
  {intent && <div className="admin-access-confirm"><h3>{intent.action==='grant'?'Add administrator?':'Remove administrator?'}</h3><p><strong>{intent.email}</strong></p><p>{intent.action==='grant'?'This account will be able to view private operations data and use administrator tools after MFA setup. It will not be allowed to manage other administrators.':'This account will lose administrator permissions. Its buyer or seller account stays unchanged.'}</p><div><button className="primary" disabled={busy} onClick={()=>void confirm()}>{busy?'Saving…':'Confirm '+(intent.action==='grant'?'addition':'removal')}</button><button className="secondary" disabled={busy} onClick={()=>setIntent(null)}>Cancel</button></div></div>}
  <p role="status">{message}</p></WorkspaceDrawer>{data && <><ul className="admin-access-list">{data.items.map(item=><li key={item.user_id}><div><strong>{item.email}</strong><small>{item.manager?'Access manager':'Administrator'} · {item.mfa_ready?'Authenticator ready':'Authenticator setup required'}</small></div>{data.can_manage&&!item.manager&&<button className="text-action" disabled={busy||Boolean(intent)} onClick={()=>prepare('revoke',item.email)}>Remove access</button>}</li>)}</ul>{!data.can_manage&&<p>Only access managers can add or remove administrators.</p>}{data.history.length>0&&<details><summary>Access history</summary><ul>{data.history.map(item=><li key={item.id}>{item.action==='grant'?'Added':'Removed'} {item.target_email||'account'} · {new Date(item.created_at).toLocaleString()}</li>)}</ul></details>}</>}
  <p role="status">{message}</p>
 </section>;
}

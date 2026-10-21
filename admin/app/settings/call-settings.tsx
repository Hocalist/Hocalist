"use client";
import { useEffect, useRef, useState } from 'react';
import { adminRpc } from '../lib/admin-client';
type Setting = { enabled: boolean; revision: number };
export function CallSettings() {
 const [setting,setSetting]=useState<Setting|null>(null);
 const [busy,setBusy]=useState(false),[message,setMessage]=useState('');
 const generation=useRef(0),gate=useRef(false);
 async function request(enabled?:boolean) {
  if(gate.current)return;
  gate.current=true;setBusy(true);setMessage('');const g=++generation.current;
  const r=await adminRpc('call_admin_settings',enabled===undefined?{}:{p_enabled:enabled,p_revision:setting?.revision});
  if(g!==generation.current)return;
  gate.current=false;setBusy(false);
  const value=r.ok?r.data as Setting:null;
  if(!value||typeof value.enabled!=='boolean'||!Number.isSafeInteger(value.revision)) {
   setSetting(null);
   setMessage(
    !r.ok&&r.state==='signed_out'?'Sign in to change the call setting.'
    :!r.ok&&r.state==='forbidden'?'Administrator access is required.'
    :!r.ok&&r.state==='unconfigured'?'The admin backend is not configured.'
    :'The setting could not be confirmed. Refresh to check its saved state before making another change.');
   return;
  }
  setSetting(value);if(enabled!==undefined)setMessage(value.enabled?'Video calling is enabled. Calling infrastructure must also be configured.':'Video calling is off. Active calls will close on their next status check.');
 }
 useEffect(()=>{void request();return()=>{++generation.current;gate.current=false;};},[]); // eslint-disable-line react-hooks/exhaustive-deps
 return <section className="section"><h2>Video calling</h2>
  <p>Optional calls between eligible chat participants. Turning this off blocks new calls and ends current calls on their next status check.</p>
  <div className="toggle-list"><label><span><strong>Allow video calls</strong><small>{setting?(setting.enabled?'On':'Off'):'Status unavailable'}</small></span>
   <input type="checkbox" role="switch" aria-label="Allow video calls" checked={setting?.enabled??false} disabled={busy||!setting} onChange={e=>void request(e.target.checked)}/></label></div>
  <p>Off does not stop an already running hosting server or its fixed hosting charges.</p>
  <button disabled={busy} onClick={()=>void request()}>{busy?'Saving or loading…':'Refresh call setting'}</button>
  {message&&<p role="status">{message}</p>}
 </section>;
}

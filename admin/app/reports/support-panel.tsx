"use client";
import { useEffect, useRef, useState } from 'react';
import { adminRpc } from '../lib/admin-client';
import { AdminIntent } from '../lib/admin-intent';
import {WorkspaceDrawer} from '../workspace-drawer';
type Case = {id:string;reason:string;body:string;status:string;response:string|null;revision:number};
export function SupportPanel(){
 const [cases,setCases]=useState<Case[]>([]),[cursor,setCursor]=useState<string|null>(null);
 const [busy,setBusy]=useState(false),[error,setError]=useState<string|null>(null);
 const [selected,setSelected]=useState<Case|null>(null),[status,setStatus]=useState('in_review'),[response,setResponse]=useState('');
 const [query,setQuery]=useState(''),[filter,setFilter]=useState('');
 const intent=useRef(new AdminIntent()),generation=useRef(0),inFlight=useRef(false);
 const [retry,setRetry]=useState<Record<string,unknown>|null>(null);
  async function load(more=false){
  const g=++generation.current;setBusy(true);setError(null);
  const result=await adminRpc('support_list',{p_limit:30,p_cursor:more?cursor:null,p_admin:true});
  if(g!==generation.current)return;setBusy(false);
  if(!result.ok){setCases([]);setSelected(null);
   setError(result.state==='signed_out'?'Sign in to review reports.'
    :result.state==='forbidden'?'Administrator access is required.'
    :result.state==='unconfigured'?'The admin backend is not configured.'
    :'Reports could not be loaded. Check your administrator session and retry.');return;}
  const data=result.data as {items?:Case[];next_cursor?:string|null};
  if(!Array.isArray(data?.items)||data.items.some(c=>typeof c.id!=='string'||typeof c.body!=='string'||typeof c.reason!=='string'||!Number.isSafeInteger(c.revision)||c.revision<1||!['open','in_review','resolved'].includes(c.status))){setError('The reports response was invalid.');return;}
  setCases(old=>more?[...old,...data.items!.filter(c=>!old.some(o=>o.id===c.id))]:data.items!);setCursor(data.next_cursor??null);
 }
 useEffect(()=>{void load();return()=>{++generation.current;};},[]); // eslint-disable-line react-hooks/exhaustive-deps
 async function save(){
  if(!selected||inFlight.current||!response.trim())return;
  const input=retry??{case_id:selected.id,expected_revision:selected.revision,status,response:response.trim()};
  const prepared=intent.current.prepare('review',input);inFlight.current=true;setBusy(true);setError(null);
  const result=await adminRpc('support_command',{p_operation:'review',p_key:prepared.key,p_input:prepared.input});
  inFlight.current=false;setBusy(false);
  if(!result.ok){setRetry(input);setError('The response was not confirmed. Retry preserves the same change. Discarding does not undo a response that may already have saved.');return;}
  intent.current.acknowledged();setRetry(null);setSelected(null);setResponse('');await load();
 }
 return <section className="section">
  <button disabled={busy||!!retry} onClick={()=>void load()}>Refresh reports</button>
  {busy&&<p role="status">Loading…</p>}{error&&<p role="alert">{error}</p>}
  <div className="filters"><label><input aria-label="Search loaded reports" placeholder="Search loaded reports…" value={query} onChange={e=>setQuery(e.target.value)}/></label><select aria-label="Report status" value={filter} onChange={e=>setFilter(e.target.value)}><option value="">All statuses</option><option value="open">Open</option><option value="in_review">In review</option><option value="resolved">Resolved</option></select></div><WorkspaceDrawer title="Review report" open={!!selected} locked={busy||!!retry} onClose={()=>setSelected(null)}>{selected&&<form className="form-grid" onSubmit={e=>{e.preventDefault();void save();}}>
   <div><h2>{selected.reason}</h2><p>Case {selected.id}</p><p style={{whiteSpace:'pre-wrap'}}>{selected.body}</p></div>
   <label>Status<select disabled={busy||!!retry} value={status} onChange={e=>setStatus(e.target.value)}><option value="open">Open</option><option value="in_review">In review</option><option value="resolved">Resolved</option></select></label>
   <label>Response to reporter<textarea required maxLength={4000} rows={5} disabled={busy||!!retry} value={response} onChange={e=>setResponse(e.target.value)}/></label>
   <div className="form-actions"><button disabled={busy||!response.trim()} className="primary">{retry?'Retry response':'Save response'}</button><button type="button" disabled={busy} onClick={()=>{intent.current.acknowledged();setRetry(null);setSelected(null);void load();}}>{retry?'Discard retry and refresh':'Cancel'}</button></div>
  </form>}
  {error&&<p role="alert">{error}</p>}</WorkspaceDrawer>{!busy&&!cases.length&&!error&&<p>No reports submitted.</p>}
  <div className="table-card"><div className="table-scroll"><table><thead><tr><th>Case</th><th>Reason</th><th>Status</th><th>Action</th></tr></thead><tbody>{cases.filter(c=>(!filter||c.status===filter)&&[c.id,c.reason,c.body].join(" ").toLowerCase().includes(query.toLowerCase())).map(c=><tr key={c.id}><td>{c.id}</td><td>{c.reason}</td><td>{c.status}</td><td><button disabled={busy||!!retry} onClick={()=>{setSelected(c);setStatus(c.status);setResponse(c.response??'');}}>Review</button></td></tr>)}</tbody></table></div></div>
  {cursor&&<button disabled={busy} onClick={()=>void load(true)}>Load more</button>}
 </section>;
}

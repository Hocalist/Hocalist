'use client';
import { useEffect, useRef, useState } from 'react';
import { adminRpc } from './lib/admin-client';
type Lead = { id: string; email: string; name: string | null; city: string | null; interest: string | null; source: string; created_at: string };
type Overview = { leads_total: number; registrations: number; download_clicks: number; first_app_opens: number; leads: Lead[]; platforms: {kind:string;platform:string;total:number}[] };
export function LaunchOverview() {
  const generation=useRef(0);
  const [data,setData]=useState<Overview|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState('');
  async function load(before?: string) {
    const request=++generation.current;
    setBusy(true); setError('');
    const result=await adminRpc('admin_launch_overview',{p_before:before??null});
    if(request!==generation.current)return;
    setBusy(false);
    if (!result.ok) {setError('Launch information could not be loaded. Check access and retry.');return;}
    const next=result.data as Overview;
    if (!next || !Array.isArray(next.leads) || !Array.isArray(next.platforms) ||
      ![next.leads_total,next.registrations,next.download_clicks,next.first_app_opens].every(Number.isSafeInteger)) {
      setError('Launch information was incomplete. Please retry.');return;
    }
    setData(old=>({...next,leads:before&&old?[...old.leads,...next.leads.filter(l=>!old.leads.some(o=>o.id===l.id))]:next.leads}));
  }
  useEffect(()=>{void load();return()=>{generation.current++;};},[]);
  return <section className="section"><div className="section-header"><div><h2>App launch & feedback</h2><p>Waitlist leads, download clicks and first signed-in app opens. These counts are separate; clicks do not prove installs.</p></div><button disabled={busy} onClick={()=>void load()}>Refresh launch information</button></div>
    {busy&&<p role="status">Loading launch information…</p>}{error&&<p role="alert">{error}</p>}
    {data&&<><div className="stats">{[['Waitlist leads',data.leads_total],['Download clicks',data.download_clicks],['First signed-in app opens',data.first_app_opens],['Registered accounts',data.registrations]].map(([label,value])=><article className="stat" key={label}><p>{label}</p><strong>{value}</strong></article>)}</div>
    <p>App opens count each account once per mobile platform from the tracking release onward. Registrations are existing accounts, not proven waitlist conversions.</p>
    <div className="table-card"><div className="table-scroll"><table><thead><tr><th>Name / email</th><th>City / area</th><th>Interest</th><th>Source</th><th>Joined</th></tr></thead><tbody>{data.leads.map(l=><tr key={l.id}><td>{l.name??'—'}<br/>{l.email}</td><td>{l.city??'—'}</td><td>{l.interest??'Not provided'}</td><td>{l.source}</td><td>{new Date(l.created_at).toLocaleDateString()}</td></tr>)}</tbody></table></div></div>
    {!data.leads.length&&<p>No waitlist leads yet.</p>}
    {data.leads.length<data.leads_total&&data.leads.length>0&&<button disabled={busy} onClick={()=>void load(data.leads.at(-1)!.id)}>Load more leads</button>}
    <div className="filters">{data.platforms.map(p=><span key={p.kind+p.platform}>{p.platform}: {p.total} {p.kind==='download_click'?'download clicks':'first signed-in opens'}</span>)}</div></>}
    <a href="/reports">Review feedback and support cases →</a>
  </section>;
}

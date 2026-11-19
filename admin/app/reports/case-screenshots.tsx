'use client';
import { useEffect, useRef, useState } from 'react';
import { adminRpc } from '../lib/admin-client';
import { requestEvidence } from '../lib/admin-evidence-client';
export function CaseScreenshots({caseId}:{caseId:string}) {
  const generation=useRef(0);
  const [loading,setLoading]=useState(true);
  const [ids,setIds]=useState<string[]>([]),[preview,setPreview]=useState<string|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
  useEffect(()=>{let active=true;generation.current++;setLoading(true);setIds([]);setPreview(null);setError('');setBusy(false);void adminRpc('admin_support_evidence',{p_case_id:caseId}).then(result=>{
    if (!active) return;
    setLoading(false);
    if(!result.ok){setError('Screenshots could not be loaded.');return;}
    const items=(result.data as {items?:unknown}).items;
    if(Array.isArray(items)&&items.every(x=>typeof x==='string'))setIds(items);
  });return()=>{active=false;generation.current++;};},[caseId]);
  useEffect(()=>()=>{if(preview)URL.revokeObjectURL(preview);},[preview]);
  async function open(id:string){const request=++generation.current;setBusy(true);setError('');const result=await requestEvidence(caseId,id,'report');if(request!==generation.current){if(result.ok)URL.revokeObjectURL(result.url);return;}setBusy(false);if(result.ok)setPreview(result.url);else setError(result.message);}
  return <div><h3>Screenshots</h3>{loading&&<p role="status">Loading screenshots…</p>}{error&&<p role="alert">{error}</p>}{ids.map((id,i)=><button type="button" key={id} disabled={busy} onClick={()=>void open(id)}>View screenshot {i+1}</button>)}{!loading&&!ids.length&&!error&&<p>No screenshots attached.</p>}{preview&&<img src={preview} alt="User-submitted feedback screenshot" style={{maxWidth:'100%',maxHeight:500,objectFit:'contain'}}/>}</div>;
}

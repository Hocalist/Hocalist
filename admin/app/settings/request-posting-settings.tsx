"use client";
import { useEffect, useRef, useState } from "react";
import { adminRpc } from "../lib/admin-client";
import { AdminIntent } from "../lib/admin-intent";
import { parseActiveRequestLimit, parseRequestPostingSettings, type RequestPostingSettings } from "../lib/request-posting-settings";
import { SectionHelp } from "../section-help";

export function RequestPostingSettingsPanel() {
  const [saved,setSaved]=useState<RequestPostingSettings|null>(null);
  const [value,setValue]=useState("");
  const [busy,setBusy]=useState(false),[message,setMessage]=useState("");
  const [pending,setPending]=useState<{p_limit:number;p_revision:number}|null>(null);
  const gate=useRef(false), generation=useRef(0), intent=useRef(new AdminIntent());
  async function load() {
    if(gate.current)return;
    gate.current=true;setBusy(true);setMessage("");const current=++generation.current;
    const result=await adminRpc("admin_request_posting_settings",{});
    if(current!==generation.current)return;
    gate.current=false;setBusy(false);
    const next=result.ok?parseRequestPostingSettings(result.data):null;
    setSaved(next);setValue(next?String(next.maximum_active_requests):"");
    if(!next)setMessage("The request limit could not be loaded. Reload it before making a change.");
  }
  useEffect(()=>{void load();return()=>{++generation.current;gate.current=false;};},[]); // eslint-disable-line react-hooks/exhaustive-deps
  async function save() {
    if(gate.current||!saved)return;
    const limit=parseActiveRequestLimit(value);
    if(limit===null){setMessage("Enter a whole number from 1 to 100.");return;}
    const fields=pending??{p_limit:limit,p_revision:saved.revision};
    const change=intent.current.prepare("request-posting-limit",fields);
    gate.current=true;setBusy(true);setMessage("");const current=++generation.current;
    const result=await adminRpc("admin_request_posting_settings",{...change.input,p_key:change.key});
    if(current!==generation.current)return;
    gate.current=false;setBusy(false);
    const next=result.ok?parseRequestPostingSettings(result.data):null;
    if(!next){setPending(fields);setMessage("Save could not be confirmed. Retry the same change, or reload the saved limit.");return;}
    intent.current.acknowledged();setPending(null);setSaved(next);setValue(String(next.maximum_active_requests));setMessage("Request limit saved.");
  }
  function discardAndReload(){intent.current.acknowledged();setPending(null);void load();}
  return <section className="section">
    <div className="page-title-line"><h2>Buyer request limit</h2><SectionHelp path="/settings/request-limits" title="Buyer request limit"/></div>
    <p>Choose how many requests a buyer can keep open at the same time.</p>
    <form className="form-grid request-posting-form" onSubmit={event=>{event.preventDefault();void save();}}>
      <label>Maximum active requests per buyer<input type="number" min="1" max="100" step="1" inputMode="numeric" required value={value} disabled={busy||!saved||!!pending} onChange={event=>setValue(event.target.value)} aria-describedby="request-limit-help"/><small id="request-limit-help">Closed, cancelled and expired requests do not count.</small></label>
      {saved&&<p>Current limit: <strong>{saved.maximum_active_requests}</strong> active requests per buyer.</p>}
      <div className="form-actions"><button className="primary" disabled={busy||!saved}>{busy?"Please wait…":pending?"Retry same change":"Save limit"}</button><button type="button" disabled={busy} onClick={discardAndReload}>Reload saved limit</button></div>
    </form>
    {message&&<p role="status">{message}</p>}
    <p>Lowering this limit keeps existing requests open. Buyers at or above the limit must close a request before posting or reopening another.</p>
  </section>;
}

"use client";
import { useEffect, useRef, useState } from "react";
import { adminRpc } from "../lib/admin-client";
import { AdminIntent } from "../lib/admin-intent";
type Reason = { code: string; label: string; active: boolean; sort_order: number; revision?: number; expected_revision?: number };
export function ReasonSettings() {
 const [items, setItems] = useState<Reason[]>([]), [code, setCode] = useState(""), [label, setLabel] = useState("");
 const [busy, setBusy] = useState(false), [message, setMessage] = useState<string | null>(null), [retry, setRetry] = useState<Reason | null>(null);
 const [loaded, setLoaded] = useState(false);
 const intent = useRef(new AdminIntent()), gate = useRef(false), generation = useRef(0);
 async function load() {
  const g = ++generation.current; setBusy(true);
  const r = await adminRpc("support_reasons", { p_include_retired: true });
  if (g !== generation.current) return;
  setBusy(false);
  if (!r.ok) {
   setItems([]); setLoaded(false);
   setMessage(
    r.state === "signed_out"
     ? "Sign in to manage report reasons. No write control is active until the session is authorized."
     : r.state === "forbidden"
     ? "Administrator access is required before report reasons can be edited."
     : r.state === "unconfigured"
     ? "The admin backend is not configured. Report reasons stay read-only."
     : "Settings could not be loaded. Check your administrator session and retry."
   );
   return;
  }
  const data = r.ok ? (r.data as { items?: Reason[] }) : null;
  if (!Array.isArray(data?.items) || data.items.some(v => typeof v.code !== "string" || typeof v.label !== "string" || typeof v.active !== "boolean" || !Number.isInteger(v.sort_order))) {
   setItems([]); setLoaded(false); setMessage("The settings response was invalid. Retry before editing.");
   return;
  }
  setItems(data.items); setLoaded(true); setMessage(null);
 }
 useEffect(() => { void load(); return () => { ++generation.current; }; }, []); // eslint-disable-line react-hooks/exhaustive-deps
 async function save(value: Reason) {
  if (gate.current || !loaded) return;
  const { revision, ...fields } = value;
  const input = { ...fields, ...(revision ? { expected_revision: revision } : {}) };
  const p = intent.current.prepare("reason.save", input);
  gate.current = true; setBusy(true); setMessage(null);
  const r = await adminRpc("support_command", { p_operation: "reason.save", p_key: p.key, p_input: p.input });
  gate.current = false; setBusy(false);
  if (!r.ok) {
   setRetry(value);
   setMessage(
    r.message && r.message.toLowerCase().includes("revision_conflict")
     ? "Another administrator changed this reason. Refresh before saving again."
     : "Save was not confirmed. Retry the same change, or discard and refresh before editing."
   );
   return;
  }
  intent.current.acknowledged(); setRetry(null); setCode(""); setLabel(""); setMessage("Saved."); await load();
 }
 return <section className="section"><button disabled={busy || !!retry} onClick={() => void load()}>Refresh settings</button>{message && <p role="status">{message}</p>}
 <form className="form-grid" onSubmit={e => { e.preventDefault(); void save({ code: code.trim(), label: label.trim(), active: true, expected_revision: items.find(r => r.code === code.trim())?.revision, sort_order: items.find(r => r.code === code.trim())?.sort_order ?? items.length }); }}>
 <fieldset disabled={busy || !!retry || !loaded} style={{ display: "contents" }}>
 <label>Reason code<input aria-describedby="reason-code-help" title="Use lowercase letters and underscores only, for example account_help." required pattern="[a-z_]{1,40}" maxLength={40} value={code} onChange={e => setCode(e.target.value)} /><small id="reason-code-help">Use lowercase letters and underscores only, for example account_help. Users see the display label instead.</small></label>
 <label>Display label<input required maxLength={100} value={label} onChange={e => setLabel(e.target.value)} /></label>
 <div className="form-actions"><button className="primary" disabled={busy || !!retry || !loaded}>Save reason</button></div>
 </fieldset></form>
 {retry && <div className="form-actions"><button disabled={busy} onClick={() => void save(retry)}>Retry same change</button><button disabled={busy} onClick={() => { intent.current.acknowledged(); setRetry(null); void load(); }}>Discard retry and refresh</button></div>}
 <div className="table-card"><table><thead><tr><th>Code</th><th>Label</th><th>Status</th><th>Action</th></tr></thead><tbody>{items.map(r => <tr key={r.code}><td>{r.code}</td><td>{r.label}</td><td>{r.active ? "Active" : "Retired"}</td><td><button disabled={busy || !!retry || !loaded} onClick={() => { setCode(r.code); setLabel(r.label); }}>Edit</button><button disabled={busy || !!retry || !loaded} onClick={() => void save({ ...r, active: !r.active })}>{r.active ? "Retire" : "Activate"}</button></td></tr>)}</tbody></table></div>
 {loaded && items.length === 0 && <p>No report reasons are configured yet. Add the first reviewed reason above.</p>}
 </section>;
}

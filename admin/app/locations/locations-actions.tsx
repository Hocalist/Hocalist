"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, type FormEvent } from "react";

import { adminCommand } from "../lib/admin-client";
import type { AdminLocation } from "../lib/admin-data";
import { WorkspaceDrawer } from "../workspace-drawer";
import { AdminIntent } from "../lib/admin-intent";

export function LocationsActions({ locations, timezones }: { locations: AdminLocation[]; timezones: string[] }) {
  const router = useRouter();
  const [editorOpen,setEditorOpen]=useState(false),[query,setQuery]=useState("");
  const [label, setLabel] = useState("");
  const [countryCode, setCountryCode] = useState("US");
  const [region, setRegion] = useState("");
  const [city, setCity] = useState("");
  const [timezone, setTimezone] = useState("");
  const [editing, setEditing] = useState<AdminLocation | null>(null);
  const intent = useRef(new AdminIntent());
  const inFlight = useRef(false);
  const [retry, setRetry] = useState<{ operation: string; input: Record<string, unknown> } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!label.trim() || busy || retry) return;
    await execute(editing ? "location.update" : "location.create", {
      ...(editing ? { location_id: editing.id, expected_revision: editing.revision } : {}),
      label: label.trim(), country_code: countryCode.trim().toUpperCase(),
      region: region.trim() || null, city: city.trim() || null,
      timezone_id: timezone || null, sort_order: editing?.sort_order ?? locations.length,
    });
  }

  async function execute(operation: string, input: Record<string, unknown>) {
    if (inFlight.current) return;
    const prepared = intent.current.prepare(operation, input);
    inFlight.current = true;
    setBusy(true);
    setMessage(null);
    const result = await adminCommand(operation, prepared.input, prepared.key);
    inFlight.current = false;
    setBusy(false);
    if (!result.ok) {
      setRetry({ operation, input: prepared.input });
      setMessage("The change was not confirmed. Retry sends the same change safely. If you discard it, refresh and check the records before making another change.");
      return;
    }
    intent.current.acknowledged();
    setRetry(null);
    setEditing(null);
    setLabel("");
    setRegion("");
    setCity("");
    setTimezone("");
    setEditorOpen(false);setMessage("Saved.");
    router.refresh();
  }

  async function setStatus(location: AdminLocation) {
    if (busy || retry) return;
    await execute("location.set_status", {
      location_id: location.id,
      expected_revision: location.revision,
      status: location.status === "active" ? "retired" : "active",
    });
  }

  function edit(location: AdminLocation) {
    setEditorOpen(true);setEditing(location); setLabel(location.label); setCountryCode(location.country_code);
    setRegion(location.region ?? ""); setCity(location.city ?? "");
    setTimezone(location.timezone_id ?? ""); setMessage(null);
  }

  return (
    <section className="section">
      <div className="section-title">
        <h2>Markets</h2><button className="primary" disabled={busy||!!retry} onClick={()=>setEditorOpen(true)}>Add market</button>
      </div>
      <WorkspaceDrawer title={editing?"Edit market":"Add market"} open={editorOpen} locked={busy||!!retry} onClose={()=>setEditorOpen(false)}><form className="form-grid" onSubmit={submit}>
        <fieldset disabled={busy || !!retry} style={{display:"contents"}}>
        <label>
          Country code
          <input
            value={countryCode}
            maxLength={2}
            onChange={(event) => setCountryCode(event.target.value)}
            placeholder="US"
          />
        </label>
        <label>
          Meeting timezone
          <select aria-label="Meeting timezone" value={timezone} onChange={event => setTimezone(event.target.value)}>
            <option value="">Unspecified / area spans multiple zones</option>
            {timezone && !timezones.includes(timezone) && <option value={timezone} disabled>{timezone} (unavailable)</option>}
            {timezones.map(zone => <option key={zone} value={zone}>{zone}</option>)}
          </select>
          <small>Choose the named zone only when it applies to this location. Broad areas can remain unspecified.</small>
        </label>
        <label>
          Region
          <input
            value={region}
            onChange={(event) => setRegion(event.target.value)}
            placeholder="NY"
          />
        </label>
        <label>
          City
          <input
            value={city}
            onChange={(event) => setCity(event.target.value)}
            placeholder="Yonkers"
          />
        </label>
        <label>
          Display label
          <input
            value={label}
            maxLength={200}
            onChange={(event) => setLabel(event.target.value)}
            placeholder="Yonkers, NY"
          />
        </label>
        <div className="form-actions">
          <button className="primary" type="submit" disabled={busy}>
            {busy ? "Saving…" : editing ? "Save changes" : "Add location"}
          </button>
          {editing && <button type="button" onClick={()=>{setEditing(null);setLabel("");setRegion("");setCity("");setTimezone("");}}>Cancel edit</button>}
        </div>
        </fieldset>
      </form>
      {message ? <p role="status">{message}</p> : null}
      {retry && <div className="form-actions">
        <button disabled={busy} onClick={()=>void execute(retry.operation,retry.input)}>Retry same change</button>
        <button disabled={busy} onClick={()=>{intent.current.acknowledged();setRetry(null);setEditing(null);setLabel("");setMessage("Retry discarded. Check refreshed records before creating another change; a previous save may have succeeded.");router.refresh();}}>Discard retry and refresh</button>
      </div>}
      </WorkspaceDrawer><div className="filters"><label><input aria-label="Search markets" placeholder="Search markets…" value={query} onChange={e=>setQuery(e.target.value)}/></label></div><div className="table-card">
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Label</th>
                <th>Country</th>
                <th>Region</th>
                <th>City</th>
                <th>Status</th>
                <th>Timezone</th>
                <th>
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {locations.filter(l=>[l.label,l.country_code,l.region,l.city,l.timezone_id,l.status].join(" ").toLowerCase().includes(query.toLowerCase())).map((location) => (
                <tr key={location.id}>
                  <td>
                    <strong>{location.label}</strong>
                  </td>
                  <td>{location.country_code}</td>
                  <td>{location.region ?? "—"}</td>
                  <td>{location.city ?? "—"}</td>
                  <td>{location.status}</td>
                  <td>{location.timezone_id ?? "Unspecified"}</td>
                  <td>
                    <button className="row-action" disabled={busy || !!retry} onClick={()=>edit(location)}>Edit</button>
                    <button
                      className="row-action"
                      disabled={busy || !!retry}
                      onClick={() => setStatus(location)}
                    >
                      {location.status === "active" ? "Retire" : "Activate"}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}

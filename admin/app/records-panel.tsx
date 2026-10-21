"use client";
import Link from "next/link";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { adminRpc } from "./lib/admin-client";
import { decodeRecordPage, RECORDS, type RecordPage, type RecordResource } from "./lib/admin-records";
import { Status } from "./components";
import { RecordDetails } from "./record-details";

export function RecordsPanel({ resource }: { resource: RecordResource }) {
  const definition = RECORDS[resource];
  const [page, setPage] = useState<RecordPage | null>(null);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [signedOut, setSignedOut] = useState(false);
  const [selectedId,setSelectedId]=useState<string|null>(null);
  const generation = useRef(0);
  const filters = useRef({ query: "", status: "" });

  async function fetchPage(cursor: string | null, append = false) {
    const current = ++generation.current;
    setSelectedId(null);
    setBusy(true); setError(null);
    const result = await adminRpc("admin_records", { p_resource: resource, p_limit: 50,
      p_cursor: cursor, p_query: filters.current.query || null, p_status: filters.current.status || null });
    if (current !== generation.current) return;
    setBusy(false);
    if (!result.ok) {
      setSignedOut(result.state === "signed_out");
      setError(result.state === "signed_out" ? "Sign in to load these records." :
        result.state === "forbidden" ? "Administrator access is required." :
        result.state === "unconfigured" ? "The admin backend is not configured." : "Records could not be loaded. Try again.");
      // Never retain private rows after an authorization failure.
      if (result.state === "signed_out" || result.state === "forbidden") setPage(null);
      return;
    }
    const decoded = decodeRecordPage(result.data);
    if (!decoded) { setError("The backend returned an invalid records page."); return; }
    setSignedOut(false);
    setPage(previous => append && previous ? {
      items: [...previous.items, ...decoded.items.filter(row => !previous.items.some(old => old.id === row.id))],
      next_cursor: decoded.next_cursor === cursor ? null : decoded.next_cursor,
    } : decoded);
  }
  useEffect(() => { void fetchPage(null); return () => { ++generation.current; }; }, [resource]); // eslint-disable-line react-hooks/exhaustive-deps
  function search(event: FormEvent) {
    event.preventDefault(); filters.current = {query: query.trim(), status}; setPage(null); void fetchPage(null);
  }
  return <>
    <form className="filters" onSubmit={search}>
      <label><span>⌕</span><input aria-label="Search records" maxLength={100} placeholder="Search displayed fields or ID" value={query} onChange={e=>setQuery(e.target.value)}/></label>
      <select aria-label="Filter status" value={status} onChange={e=>setStatus(e.target.value)}><option value="">All statuses</option>{definition.statuses.map(s=><option key={s} value={s}>{s}</option>)}</select>
      <button disabled={busy} type="submit">Search</button>
      <button disabled={busy} type="button" onClick={()=>{setPage(null);void fetchPage(null);}}>Refresh</button>
    </form>
    {error && <div role="alert" className="demo-notice"><span>{error}</span>{signedOut && <Link href="/login">Sign in</Link>}<button onClick={()=>void fetchPage(null)} disabled={busy}>Try again</button></div>}
    {busy && <p role="status">Loading records…</p>}
    {page && <div className="table-card"><div className="table-scroll"><table><thead><tr>{definition.columns.map(c=><th key={c}>{c}</th>)}<th><span className="sr-only">Details</span></th></tr></thead><tbody>
      {page.items.length ? page.items.map(row=><tr key={row.id}>{row.cells.map((cell,i)=><td key={i}>{i===definition.statusIndex ? <Status>{cell}</Status> : cell || "—"}</td>)}<td><button type="button" onClick={()=>setSelectedId(row.id)}>View details ↗</button></td></tr>) : <tr><td colSpan={7}>{(filters.current.query || filters.current.status) ? "No records match the current search or status filter." : "No records recorded yet."}</td></tr>}
    </tbody></table></div><footer className="pagination"><span>{page.items.length} records loaded · ordered by ID</span>{page.next_cursor && <button disabled={busy} onClick={()=>void fetchPage(page.next_cursor,true)}>Load more</button>}</footer></div>}
    {page?.items.filter(row=>row.id===selectedId).map(row=><RecordDetails key={row.id} columns={definition.columns} cells={row.cells} statusIndex={definition.statusIndex} onClose={()=>setSelectedId(null)}/>)}
  </>;
}

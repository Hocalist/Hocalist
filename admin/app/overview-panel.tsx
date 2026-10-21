"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { adminRpc } from "./lib/admin-client";
import { decodeOverview, OVERVIEW_LABELS } from "./lib/admin-records";
import { Stat } from "./components";

const METRIC_LINKS: Record<keyof typeof OVERVIEW_LABELS, string> = {
  active_memberships: "/users",
  open_requests: "/requests",
  submitted_offers: "/offers",
  listings_in_review: "/moderation",
  test_subscriptions: "/billing",
};

const QUEUES = [
  {
    href: "/moderation",
    title: "Store listings in review",
    body: "Approve or reject submitted listings with a recorded reason before they appear in discovery.",
    metric: "listings_in_review" as const,
  },
  {
    href: "/reports",
    title: "Support reports",
    body: "Review submitted concerns, respond to the reporter and keep seller health separate from a single report.",
  },
  {
    href: "/billing",
    title: "Billing reconciliation",
    body: "Stripe TEST subscriptions plus the separate HocaCredit batch and buyer reward ledgers. Withdrawals have their own queue.",
  },
  {
    href: "/events",
    title: "Failed provider events",
    body: "Stripe TEST receipt and reconciliation events that still need attention, with sanitized error classes. Email bounce ingestion is not connected.",
  },
  {
    href: "/billing/config",
    title: "Commercial configuration",
    body: "Admin-managed deposit options and buyer reward policy with carried revisions. No rate is seeded or invented.",
  },
  {
    href: "/audit",
    title: "Audit log",
    body: "Reviewed administrator, moderation, support, trust and commercial actions from their existing append-only records.",
  },
];

export function OverviewPanel() {
  const [data,setData]=useState<ReturnType<typeof decodeOverview>>(null);
  const [busy,setBusy]=useState(true);
  const [error,setError]=useState<string|null>(null);
  const generation=useRef(0);
  async function refresh() {
    const current=++generation.current;setBusy(true);setError(null);
    const result=await adminRpc("admin_overview",{});
    if(current!==generation.current)return;
    setBusy(false);
    if(!result.ok){setData(null);setError(result.state==="signed_out"?"Sign in to view the overview.":result.state==="forbidden"?"Administrator access is required.":"The overview is unavailable. Check configuration and try again.");return;}
    const decoded=decodeOverview(result.data);setData(decoded);
    if(!decoded)setError("The backend returned an invalid overview.");
  }
  useEffect(()=>{void refresh();return()=>{++generation.current;};},[]);
  return <><button onClick={()=>void refresh()} disabled={busy}>Refresh overview</button>
    {busy&&<p role="status">Loading overview…</p>}
    {error&&<div role="alert" className="demo-notice"><span>{error}</span><Link href="/login">Sign in</Link></div>}
    {data&&<div className="stats">{Object.entries(OVERVIEW_LABELS).map(([key,label])=><Stat key={key} label={label} value={String(data[key as keyof typeof data])} note={key==="test_subscriptions"?"Stripe test mode only":key==="listings_in_review"?"Needs an admin decision":"Current recorded state"} href={METRIC_LINKS[key as keyof typeof data]}/>)}</div>}
    <section className="section">
      <div className="section-title"><h2>Review queues</h2></div>
      <div className="overview-queues">
        {QUEUES.map(queue=><article key={queue.href} className="overview-queue">
          <h3>{queue.title}</h3>
          <p>{queue.body}</p>
          {queue.metric&&data&&<strong>{data[queue.metric]} waiting</strong>}
          <Link href={queue.href}>Open queue →</Link>
        </article>)}
      </div>
    </section>
    <div className="boundary"><strong>Offline item payments</strong><span>Marketplace counts are operational records. They do not represent collected item revenue or completed transactions.</span></div>
  </>;
}

"use client";

import { useEffect, useState, type FormEvent } from "react";
import { adminRpc } from "./lib/admin-client";

const ALARM_POLL_MS = 15_000;

export function SafetyAlarmBanner() {
  const [count, setCount] = useState(0);
  const [unavailable, setUnavailable] = useState(false);

  useEffect(() => {
    let active = true;
    let pending = false;

    async function refresh() {
      if (pending || document.visibilityState !== "visible") return;
      pending = true;
      const result = await adminRpc("admin_safety_alarm_count", {});
      pending = false;
      if (!active) return;
      if (result.ok && typeof result.data === "number") {
        setCount(result.data);
        setUnavailable(false);
      } else if (!result.ok && (result.state === "signed_out" || result.state === "forbidden")) {
        setCount(0);
        setUnavailable(false);
      } else {
        setUnavailable(true);
      }
    }

    void refresh();
    const timer = window.setInterval(refresh, ALARM_POLL_MS);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, []);

  return (
    <div aria-live="polite" aria-atomic="true">
      {count > 0 && (
        <div className="safety-alarm-banner">
          <span><strong>Safety alarm</strong> · {count} {count === 1 ? "report needs" : "reports need"} immediate review{unavailable && " (last checked)"}</span>
          <a href="/trust">Open priority queue</a>
        </div>
      )}
      {unavailable && <p role="status" className="boundary">Safety alarm updates are temporarily unavailable.</p>}
    </div>
  );
}

type Rule = { id: string; phrase: string; enabled: boolean; revision: number };

function isRule(value: unknown): value is Rule {
  if (!value || typeof value !== "object") return false;
  const row = value as Partial<Rule>;
  return typeof row.id === "string" && typeof row.phrase === "string" &&
    typeof row.enabled === "boolean" && Number.isSafeInteger(row.revision);
}

export function SafetyPhraseRules() {
  const [rules, setRules] = useState<Rule[] | null>(null);
  const [editing, setEditing] = useState<Rule | null>(null);
  const [phrase, setPhrase] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  async function load() {
    setBusy(true);
    setError("");
    const result = await adminRpc("admin_safety_phrase_rules", {});
    setBusy(false);
    if (result.ok && Array.isArray(result.data) && result.data.every(isRule)) {
      setRules(result.data);
    } else {
      setError("Could not load alarm phrases. Refresh the list to retry.");
    }
  }

  function edit(rule: Rule | null) {
    setEditing(rule);
    setPhrase(rule?.phrase ?? "");
    setEnabled(rule?.enabled ?? true);
    setNotice("");
    setError("");
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    setNotice("");
    const result = await adminRpc("admin_save_safety_phrase", {
      p_phrase: phrase.trim(),
      p_enabled: enabled,
      p_id: editing?.id ?? null,
      p_revision: editing?.revision ?? null,
    });
    if (!result.ok) {
      setBusy(false);
      setError("Could not save the phrase. Make sure it is unique and contains at least two words. If another admin edited it, refresh the list and select it again.");
      return;
    }
    edit(null);
    setNotice("Alarm phrase saved.");
    await load();
  }

  return (
    <details className="section safety-rule-list">
      <summary><strong>Manage safety alarm phrases</strong></summary>
      <p>Active phrases flag new Support reports for immediate review. Use specific, multi-word phrases. Matches can include quotations or misunderstandings, so read the report before making a decision.</p>
      <button type="button" onClick={() => { edit(null); void load(); }} disabled={busy}>
        {rules ? "Refresh phrases" : "Load phrases"}
      </button>
      {error && <p role="alert">{error}</p>}
      {notice && <p role="status">{notice}</p>}
      {rules && (
        <>
          <form className="safety-rule-form" onSubmit={save}>
            <label>
              {editing ? "Edit phrase" : "New phrase"}
              <input required minLength={8} maxLength={120} value={phrase} disabled={busy}
                onChange={(event) => setPhrase(event.target.value)} />
            </label>
            <label><input type="checkbox" checked={enabled} disabled={busy}
              onChange={(event) => setEnabled(event.target.checked)} /> Active</label>
            <button type="submit" disabled={busy || phrase.trim().length < 8}>Save phrase</button>
            {editing && <button type="button" onClick={() => edit(null)} disabled={busy}>Cancel edit</button>}
          </form>
          <ul className="safety-phrases">
            {rules.map((rule) => (
              <li key={rule.id}>
                <span>{rule.phrase}</span>
                <span className={rule.enabled ? "status success" : "status neutral"}>{rule.enabled ? "Active" : "Inactive"}</span>
                <button type="button" onClick={() => edit(rule)} disabled={busy}>Edit<span className="sr-only"> {rule.phrase}</span></button>
              </li>
            ))}
          </ul>
        </>
      )}
    </details>
  );
}

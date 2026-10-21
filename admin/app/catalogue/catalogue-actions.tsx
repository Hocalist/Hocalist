"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, type FormEvent } from "react";

import { adminCommand } from "../lib/admin-client";
import type { AdminCatalogueCategory } from "../lib/admin-data";
import { AdminIntent } from "../lib/admin-intent";

type EntryType = "category" | "group" | "option";

function catalogueError(message: string, state?: string): string {
  if (state === "signed_out") return "Sign in again to edit the catalogue.";
  if (state === "forbidden") return "Administrator access is required.";
  if (state === "unconfigured") return "The admin backend is not configured.";
  const normalized = message.toLowerCase();
  if (normalized.includes("revision_conflict")) {
    return "Another administrator changed this entry. Refresh before editing it again.";
  }
  if (normalized.includes("idempotency_conflict")) {
    return "This operation key was already used for a different change. Refresh before editing again.";
  }
  if (normalized.includes("unknown_field") || normalized.includes("invalid_")) {
    return "The backend rejected these values. Check the label and parent selection.";
  }
  return "The change was not confirmed. Retry the same change or refresh the catalogue.";
}

export function CatalogueActions({
  categories,
}: {
  categories: AdminCatalogueCategory[];
}) {
  const router = useRouter();
  const [entryType, setEntryType] = useState<EntryType>("category");
  const [label, setLabel] = useState("");
  const [scope, setScope] = useState("product");
  const [parentId, setParentId] = useState("");
  const [selectionMode, setSelectionMode] = useState("single");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [retry, setRetry] = useState<{ operation: string; input: Record<string, unknown> } | null>(
    null,
  );
  const intent = useRef(new AdminIntent());
  const inFlight = useRef(false);

  const groups = categories.flatMap((category) =>
    category.groups.map((group) => ({ ...group, categoryLabel: category.label })),
  );

  async function execute(operation: string, input: Record<string, unknown>) {
    if (inFlight.current) return;
    const prepared = intent.current.prepare(operation, input);
    inFlight.current = true;
    setBusy(true);
    setError(null);
    setMessage(null);
    const result = await adminCommand(operation, prepared.input, prepared.key);
    inFlight.current = false;
    setBusy(false);
    if (!result.ok) {
      setRetry({ operation, input: prepared.input });
      setError(catalogueError(result.message, result.state));
      return;
    }
    intent.current.acknowledged();
    setRetry(null);
    setLabel("");
    setMessage("Saved. The catalogue was refreshed.");
    router.refresh();
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!label.trim() || busy || retry) return;
    if (entryType === "category") {
      await execute("category.create", {
        label: label.trim(),
        scope,
        sort_order: categories.length,
      });
    } else if (entryType === "group") {
      if (!parentId) {
        setError("Choose a category first.");
        return;
      }
      await execute("group.create", {
        category_id: parentId,
        label: label.trim(),
        selection_mode: selectionMode,
        is_required: false,
        sort_order: 0,
      });
    } else {
      if (!parentId) {
        setError("Choose an option group first.");
        return;
      }
      await execute("option.create", {
        group_id: parentId,
        label: label.trim(),
        sort_order: 0,
      });
    }
  }

  async function setStatus(
    type: "category" | "option_group" | "option",
    id: string,
    revision: number,
    status: string,
  ) {
    if (busy || retry) return;
    await execute("entry.set_status", {
      entry_type: type,
      entry_id: id,
      expected_revision: revision,
      status,
    });
  }

  return (
    <section className="section">
      <div className="section-title">
        <h2>Add catalogue entry</h2>
      </div>
      <form className="form-grid" onSubmit={submit}>
        <fieldset disabled={busy || !!retry} style={{ display: "contents" }}>
        <label>
          Entry type
          <select
            value={entryType}
            onChange={(event) => {
              setEntryType(event.target.value as EntryType);
              setParentId("");
            }}
          >
            <option value="category">Category</option>
            <option value="group">Option group</option>
            <option value="option">Option</option>
          </select>
        </label>
        {entryType === "category" ? (
          <label>
            Scope
            <select value={scope} onChange={(event) => setScope(event.target.value)}>
              <option value="product">Product</option>
              <option value="service">Service</option>
              <option value="both">Both</option>
            </select>
          </label>
        ) : (
          <label>
            {entryType === "group" ? "Parent category" : "Parent option group"}
            <select
              value={parentId}
              onChange={(event) => setParentId(event.target.value)}
            >
              <option value="">Select…</option>
              {entryType === "group"
                ? categories.map((category) => (
                    <option key={category.id} value={category.id}>
                      {category.label}
                    </option>
                  ))
                : groups.map((group) => (
                    <option key={group.id} value={group.id}>
                      {group.categoryLabel} · {group.label}
                    </option>
                  ))}
            </select>
          </label>
        )}
        {entryType === "group" ? (
          <label>
            Selection
            <select
              value={selectionMode}
              onChange={(event) => setSelectionMode(event.target.value)}
            >
              <option value="single">Single choice</option>
              <option value="multiple">Multiple choice</option>
            </select>
          </label>
        ) : null}
        <label>
          Label
          <input
            value={label}
            onChange={(event) => setLabel(event.target.value)}
            maxLength={120}
            placeholder="Visible to buyers and sellers"
          />
        </label>
        <div className="form-actions">
          <button className="primary" type="submit" disabled={busy || !!retry}>
            {busy ? "Saving…" : "Add entry"}
          </button>
        </div>
        </fieldset>
      </form>
      {error ? (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          <button type="button" disabled={busy} onClick={() => router.refresh()}>
            Refresh catalogue
          </button>
        </div>
      ) : null}
      {message ? <p role="status">{message}</p> : null}
      {retry && (
        <div className="form-actions">
          <button disabled={busy} onClick={() => void execute(retry.operation, retry.input)}>
            Retry same change
          </button>
          <button
            disabled={busy}
            onClick={() => {
              intent.current.acknowledged();
              setRetry(null);
              setError(null);
              setMessage("Retry discarded. The catalogue was refreshed; check whether the change saved.");
              router.refresh();
            }}
          >
            Discard retry and refresh
          </button>
        </div>
      )}
      <div className="table-card">
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Entry</th>
                <th>Scope / mode</th>
                <th>Status</th>
                <th>Revision</th>
                <th>
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {categories.map((category) => (
                <CategoryRows
                  key={category.id}
                  category={category}
                  busy={busy || !!retry}
                  onStatus={setStatus}
                />
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}

function CategoryRows({
  category,
  busy,
  onStatus,
}: {
  category: AdminCatalogueCategory;
  busy: boolean;
  onStatus: (
    type: "category" | "option_group" | "option",
    id: string,
    revision: number,
    status: string,
  ) => void;
}) {
  return (
    <>
      <tr>
        <td>
          <strong>{category.label}</strong>
        </td>
        <td>{category.scope}</td>
        <td>{category.status}</td>
        <td>{category.revision}</td>
        <td>
          <StatusButton
            busy={busy}
            status={category.status}
            onToggle={() =>
              onStatus(
                "category",
                category.id,
                category.revision,
                category.status === "active" ? "retired" : "active",
              )
            }
          />
        </td>
      </tr>
      {category.groups.map((group) => (
        <GroupRows
          key={group.id}
          group={group}
          busy={busy}
          onStatus={onStatus}
        />
      ))}
    </>
  );
}

function GroupRows({
  group,
  busy,
  onStatus,
}: {
  group: AdminCatalogueCategory["groups"][number];
  busy: boolean;
  onStatus: (
    type: "category" | "option_group" | "option",
    id: string,
    revision: number,
    status: string,
  ) => void;
}) {
  return (
    <>
      <tr>
        <td style={{ paddingLeft: 28 }}>
          {group.label}
          {group.is_required ? " (required)" : ""}
        </td>
        <td>{group.selection_mode}</td>
        <td>{group.status}</td>
        <td>{group.revision}</td>
        <td>
          <StatusButton
            busy={busy}
            status={group.status}
            onToggle={() =>
              onStatus(
                "option_group",
                group.id,
                group.revision,
                group.status === "active" ? "retired" : "active",
              )
            }
          />
        </td>
      </tr>
      {group.options.map((option) => (
        <tr key={option.id}>
          <td style={{ paddingLeft: 48 }}>{option.label}</td>
          <td>option</td>
          <td>{option.status}</td>
          <td>{option.revision}</td>
          <td>
            <StatusButton
              busy={busy}
              status={option.status}
              onToggle={() =>
                onStatus(
                  "option",
                  option.id,
                  option.revision,
                  option.status === "active" ? "retired" : "active",
                )
              }
            />
          </td>
        </tr>
      ))}
    </>
  );
}

function StatusButton({
  busy,
  status,
  onToggle,
}: {
  busy: boolean;
  status: string;
  onToggle: () => void;
}) {
  return (
    <button className="row-action" disabled={busy} onClick={onToggle}>
      {status === "active" ? "Retire" : "Activate"}
    </button>
  );
}

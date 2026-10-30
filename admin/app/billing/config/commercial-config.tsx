"use client";

import { useRef, useState, type FormEvent } from "react";

import { FieldHelp } from "../../field-help";
import { SectionTabs } from "../../section-tabs";
import { adminRpc, creditAdminCommand } from "../../lib/admin-client";
import {
  beginDepositOptionEdit,
  beginRewardPolicyDraft,
  commercialErrorMessage,
  decodeCommercialConfig,
  depositOptionStale,
  formatMinorInput,
  newDepositOptionDraft,
  rebaseDepositOptionDraft,
  rebaseRewardPolicyDraft,
  rewardPolicyStale,
  validateDepositOptionDraft,
  validateRewardPolicyDraft,
  type CommercialConfig,
  type DepositOptionDraft,
  type DepositOptionRow,
  type RewardPolicyDraft,
} from "../../lib/admin-commercial";
import { AdminIntent } from "../../lib/admin-intent";
import { PlanDepositRates } from "./plan-deposit-rates";

export function CommercialConfigPanel({ initial }: { initial: CommercialConfig }) {
  const [config, setConfig] = useState(initial);
  const [draft, setDraft] = useState<DepositOptionDraft>(() => newDepositOptionDraft());
  const [policyDraft, setPolicyDraft] = useState<RewardPolicyDraft>(() =>
    beginRewardPolicyDraft(initial.reward_policy),
  );
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [retry, setRetry] = useState<{ operation: string; input: Record<string, unknown> } | null>(null);
  const intent = useRef(new AdminIntent());
  const inFlight = useRef(false);

  const depositStale = draft.id !== null && depositOptionStale(draft, config);
  const policyStale = rewardPolicyStale(policyDraft, config);
  const conflicted = error !== null && retry !== null;

  async function reload(): Promise<CommercialConfig | null> {
    const result = await adminRpc("admin_commercial_config", {});
    if (!result.ok) {
      setError(
        result.state === "signed_out"
          ? "Sign in again to load the commercial configuration."
          : result.state === "forbidden"
          ? "Administrator access is required."
          : "The configuration could not be reloaded. Refresh the page before editing.",
      );
      return null;
    }
    const decoded = decodeCommercialConfig(result.data);
    if (!decoded) {
      setError("The backend returned an invalid configuration. Refresh the page before editing.");
      return null;
    }
    setConfig(decoded);
    return decoded;
  }

  async function execute(operation: string, input: Record<string, unknown>) {
    if (inFlight.current) return;
    const prepared = intent.current.prepare(operation, input);
    inFlight.current = true;
    setBusy(true);
    setError(null);
    setMessage(null);
    const result = await creditAdminCommand(operation, prepared.input, prepared.key);
    inFlight.current = false;
    setBusy(false);
    if (!result.ok) {
      setRetry({ operation, input: prepared.input });
      setError(commercialErrorMessage(result));
      // A conflict means the server row moved on; reload so the stale draft is
      // visible and an explicit rebase/discard choice can be offered.
      if (result.message.toLowerCase().includes("revision_conflict")) {
        await reload();
      }
      return;
    }
    intent.current.acknowledged();
    setRetry(null);
    if (operation === "reward_policy.set") {
      setMessage("Saved. The configuration was reloaded from the backend.");
      const decoded = await reload();
      if (!decoded) {
        setMessage("Saved, but the refreshed configuration could not be loaded. Refresh the page.");
        return;
      }
      setPolicyDraft(beginRewardPolicyDraft(decoded.reward_policy));
      return;
    }
    setDraft(newDepositOptionDraft());
    setMessage("Saved. The configuration was reloaded from the backend.");
    if (!(await reload())) {
      setMessage("Saved, but the refreshed configuration could not be loaded. Refresh the page.");
    }
  }

  async function saveOption(event: FormEvent) {
    event.preventDefault();
    if (busy || retry) return;
    if (depositStale) {
      setError(
        "This option changed on the server since you opened it. Reapply your values on the current revision or discard your draft first.",
      );
      return;
    }
    const validated = validateDepositOptionDraft(draft);
    if (!validated.ok) {
      setError(validated.message);
      return;
    }
    await execute("deposit_option.set", validated.value);
  }

  async function retireOption(option: DepositOptionRow) {
    if (busy || retry) return;
    if (draft.id === option.id && depositStale) {
      setError("This option changed on the server. Refresh the row before retiring it.");
      return;
    }
    await execute("deposit_option.retire", {
      id: option.id,
      expected_revision: option.revision,
    });
  }

  async function savePolicy(event: FormEvent) {
    event.preventDefault();
    if (busy || retry) return;
    if (policyStale) {
      setError(
        "The reward policy changed on the server since this form was opened. Reapply your values on the current revision or discard your draft first.",
      );
      return;
    }
    const validated = validateRewardPolicyDraft(policyDraft);
    if (!validated.ok) {
      setError(validated.message);
      return;
    }
    await execute("reward_policy.set", validated.value);
  }

  function editOption(option: DepositOptionRow) {
    setDraft(beginDepositOptionEdit(option));
    setMessage(null);
    setError(null);
  }

  function rebaseDeposit() {
    const rebased = rebaseDepositOptionDraft(draft, config);
    if (!rebased) {
      setError("That option no longer exists. Discard your draft and review the current list.");
      return;
    }
    intent.current.acknowledged();
    setRetry(null);
    setDraft(rebased);
    setError(null);
    setMessage(
      `Draft reapplied on the current revision (${rebased.revision}). Review the values and save again.`,
    );
  }

  function discardDeposit() {
    intent.current.acknowledged();
    setRetry(null);
    setError(null);
    const current = draft.id
      ? config.deposit_options.find((option) => option.id === draft.id)
      : null;
    setDraft(current ? beginDepositOptionEdit(current) : newDepositOptionDraft());
    setMessage("Draft discarded. The form now shows the current server values.");
  }

  function rebasePolicy() {
    intent.current.acknowledged();
    setRetry(null);
    setPolicyDraft(rebaseRewardPolicyDraft(policyDraft, config));
    setError(null);
    setMessage(
      `Reward draft reapplied on the current revision (${config.reward_policy?.revision ?? "unconfigured"}). Review the values and save again.`,
    );
  }

  function discardPolicy() {
    intent.current.acknowledged();
    setRetry(null);
    setError(null);
    setPolicyDraft(beginRewardPolicyDraft(config.reward_policy));
    setMessage("Reward draft discarded. The form now shows the current server values.");
  }

  return (
    <section className="section">
      {error && (
        <div role="alert" className="demo-notice">
          <span>{error}</span>
          {!conflicted && (
            <button type="button" disabled={busy} onClick={() => void reload()}>
              Refresh configuration
            </button>
          )}
        </div>
      )}
      {message && <p role="status">{message}</p>}
      {config.paygo_plan_rates && <PlanDepositRates prepaid={false} rows={config.paygo_plan_rates.map(r=>({plan_code:r.plan_code,amount_minor:0,initial_fee_minor:r.initial_minor,winning_total_minor:r.winning_minor,rate_version:'paygo',revision:r.revision}))} busy={busy||!!retry} onSave={input=>execute("paygo_plan_rate.set",input)} />}
      {config.plan_deposit_rates && <PlanDepositRates rows={config.plan_deposit_rates} busy={busy || !!retry} onSave={input=>execute("plan_deposit_rate.set",input)} />}
      {config.plan_deposit_rates && <p>Set new-deposit fees in “Fees by seller plan” above. The pack controls below manage availability and order; their previous fee fields are historical and do not set the plan rates.</p>}
      {retry && (
        <div className="form-actions">
          <button disabled={busy} onClick={() => void execute(retry.operation, retry.input)}>
            Retry same change
          </button>
          <button
            disabled={busy}
            type="button"
            onClick={() => {
              intent.current.acknowledged();
              setRetry(null);
              setError(null);
              setMessage("Retry discarded. The configuration was reloaded; check whether the change saved before editing again.");
              void reload();
            }}
          >
            Discard retry and refresh
          </button>
        </div>
      )}

      <SectionTabs label="Deposit and reward settings" sections={[{title:"Deposit options",content:<><h2>Deposit options <FieldHelp label="Deposit options">These options set the credit purchase amount and fees for future purchases. Existing credit batches keep their original rates.</FieldHelp></h2>
      <p>
        A deposit option is the admin-managed amount and the fee rates frozen into
        each new batch at purchase. Editing or retiring an option never reprices an
        existing batch or reservation. Nothing is seeded here: with no active
        option, seller targeting stays explicitly unavailable.
      </p>
      {depositStale && (
        <div role="alert" className="demo-notice">
          <strong>This option changed on the server</strong>
          <span>
            Your draft was opened at revision {draft.revision}; the server is now at
            revision{" "}
            {config.deposit_options.find((option) => option.id === draft.id)?.revision ?? "removed"}.
            Saving upgrades nothing silently: reapply your values on the current
            revision or discard your draft.
          </span>
          <button type="button" disabled={busy || !!retry} onClick={rebaseDeposit}>
            Reapply my values on the current revision
          </button>
          <button type="button" disabled={busy || !!retry} onClick={discardDeposit}>
            Discard my draft and load current values
          </button>
        </div>
      )}
      {config.deposit_options.length === 0 ? (
        <div className="demo-notice">
          <strong>No deposit options configured</strong>
          <span>
            Credit deposits are not purchasable and targeting fees cannot be
            reserved until an administrator adds a reviewed option. No rate is
            inferred from another tier or batch.
          </span>
        </div>
      ) : (
        <div className="table-card">
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Amount</th>
                  <th>Initial fee</th>
                  <th>Total fee after winning</th>
                  <th>Rate version</th>
                  <th>Status</th>
                  <th>Order</th>
                  <th>Revision</th>
                  <th>
                    <span className="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {config.deposit_options.map((option) => (
                  <tr key={option.id}>
                    <td>
                      <strong>{formatMinorInput(option.amount_minor)}</strong>
                    </td>
                    <td>{formatMinorInput(option.initial_fee_minor)}</td>
                    <td>{formatMinorInput(option.winning_total_minor)}</td>
                    <td>{option.rate_version}</td>
                    <td>{option.active ? "Active" : "Retired"}</td>
                    <td>{option.sort_order}</td>
                    <td>{option.revision}</td>
                    <td>
                      <button
                        className="row-action"
                        disabled={busy || !!retry}
                        onClick={() => editOption(option)}
                      >
                        {draft.id === option.id ? "Editing" : "Edit"}
                      </button>
                      {option.active && (
                        <button
                          className="row-action"
                          disabled={busy || !!retry}
                          onClick={() => void retireOption(option)}
                        >
                          Retire
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div className="fee-help-line"><FieldHelp label="Initial and winning fees">The initial fee is charged after the buyer replies to the seller for that deal. The total winning fee includes it. For example, an initial fee of 1.55 and total winning fee of 3.75 means another 2.20 is charged on a win. These are examples, not a change to your saved rates.</FieldHelp><span>How initial and winning fees work</span></div><form className="form-grid" onSubmit={saveOption}>
        <fieldset disabled={busy || !!retry || depositStale} style={{ display: "contents" }}>
          <label>
            Amount
            <input
              inputMode="decimal"
              maxLength={16}
              placeholder="20.00"
              value={draft.amount}
              onChange={(event) => setDraft({ ...draft, amount: event.target.value })}
            />
          </label>
          <label>
            Initial fee
            <input
              inputMode="decimal"
              maxLength={16}
              placeholder="1.55"
              disabled={!!config.plan_deposit_rates}
              value={draft.initialFee}
              onChange={(event) => setDraft({ ...draft, initialFee: event.target.value })}
            />
          </label>
          <label>
            Winning total
            <input
              inputMode="decimal"
              maxLength={16}
              placeholder="3.75"
              disabled={!!config.plan_deposit_rates}
              value={draft.winningTotal}
              onChange={(event) => setDraft({ ...draft, winningTotal: event.target.value })}
            />
          </label>
          <label>
            Rate version
            <input
              maxLength={100}
              placeholder="reviewed-2026-09"
              value={draft.rateVersion}
              onChange={(event) => setDraft({ ...draft, rateVersion: event.target.value })}
            />
          </label>
          <label>
            Sort order
            <input
              inputMode="numeric"
              maxLength={6}
              value={draft.sortOrder}
              onChange={(event) => setDraft({ ...draft, sortOrder: event.target.value })}
            />
          </label>
          <label>
            Availability
            <select
              value={draft.active ? "active" : "retired"}
              onChange={(event) => setDraft({ ...draft, active: event.target.value === "active" })}
            >
              <option value="active">Active (purchasable)</option>
              <option value="retired">Retired (hidden from purchase)</option>
            </select>
          </label>
          <div className="form-actions">
            <button className="primary" type="submit" disabled={busy || depositStale}>
              {busy ? "Saving…" : draft.id ? "Save option" : "Add option"}
            </button>
            {draft.id && (
              <button type="button" onClick={() => setDraft(newDepositOptionDraft())}>
                Cancel edit
              </button>
            )}
          </div>
        </fieldset>
      </form>

      </>},{title:"Buyer rewards",content:<><h2>Buyer reward policy <FieldHelp label="Buyer rewards">Set the reward amounts used for eligible confirmed purchases. Rewards are separate from seller credits and do not pay for the item itself.</FieldHelp></h2>
      {config.reward_policy === null ? (
        <div className="demo-notice">
          <strong>Reward policy not configured</strong>
          <span>
            No reward rate is inferred and no sale is blocked by this state. Set a
            reviewed normal/late reward and rule version to enable accrual
            configuration.
          </span>
        </div>
      ) : (
        <p>
          Configured policy revision {config.reward_policy.revision} · rule version{" "}
          {config.reward_policy.rule_version}
        </p>
      )}
      {policyStale && (
        <div role="alert" className="demo-notice">
          <strong>The reward policy changed on the server</strong>
          <span>
            Your draft was opened at revision {policyDraft.revision ?? "unconfigured"};
            the server is now at {config.reward_policy?.revision ?? "unconfigured"}.
            Saving upgrades nothing silently: reapply your values on the current
            revision or discard your draft.
          </span>
          <button type="button" disabled={busy || !!retry} onClick={rebasePolicy}>
            Reapply my values on the current revision
          </button>
          <button type="button" disabled={busy || !!retry} onClick={discardPolicy}>
            Discard my draft and load current values
          </button>
        </div>
      )}
      <form className="form-grid" onSubmit={savePolicy}>
        <fieldset disabled={busy || !!retry || policyStale} style={{ display: "contents" }}>
          <label>
            Normal reward
            <input
              inputMode="decimal"
              maxLength={16}
              placeholder="0.15"
              value={policyDraft.normal}
              onChange={(event) => setPolicyDraft({ ...policyDraft, normal: event.target.value })}
            />
          </label>
          <label>
            Late-window reward
            <input
              inputMode="decimal"
              maxLength={16}
              placeholder="0.30"
              value={policyDraft.late}
              onChange={(event) => setPolicyDraft({ ...policyDraft, late: event.target.value })}
            />
          </label>
          <label>
            Late window (hours, optional)
            <input
              inputMode="numeric"
              maxLength={3}
              placeholder="12"
              value={policyDraft.lateWindowHours}
              onChange={(event) =>
                setPolicyDraft({ ...policyDraft, lateWindowHours: event.target.value })
              }
            />
          </label>
          <label>
            Rule version
            <input
              maxLength={100}
              placeholder="reward-2026-09"
              value={policyDraft.ruleVersion}
              onChange={(event) => setPolicyDraft({ ...policyDraft, ruleVersion: event.target.value })}
            />
          </label>
          <div className="form-actions">
            <button className="primary" type="submit" disabled={busy || policyStale}>
              {busy ? "Saving…" : config.reward_policy ? "Save reward policy" : "Set reward policy"}
            </button>
          </div>
        </fieldset>
      </form>

      </>}]} /><div className="boundary">
        <strong>Immutable batch rates</strong>
        <span>
          Historical batches and open reservations keep the rates recorded at
          purchase. These editors change only what a future purchase snapshots,
          and every save carries the revision captured when the draft was opened.
        </span>
      </div>
    </section>
  );
}

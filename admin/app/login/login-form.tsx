"use client";
import { AuthenticatorSetup } from "../settings/authenticator-setup";

import Link from "next/link";
import { PasswordInput } from "../password-input";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState, type FormEvent } from "react";

import {
  cancelMfa,
  fetchPendingFactors,
  requestMfaChallenge,
  verifyMfa,
  type MfaFactorView,
} from "../lib/admin-mfa-client";

type Step = "credentials" | "challenge" | "enrollment";

export function LoginForm({
  configured,
  policyRequired,
  pending,
}: {
  configured: boolean;
  policyRequired: boolean;
  pending: boolean;
}) {
  const router = useRouter();
  const [step, setStep] = useState<Step>(pending && policyRequired ? "challenge" : "credentials");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [factors, setFactors] = useState<MfaFactorView[]>([]);
  const [factorId, setFactorId] = useState("");
  const [challengeId, setChallengeId] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const startChallenge = useCallback(async (selected: string) => {
    setBusy(true);
    setMessage(null);
    setChallengeId("");
    const result = await requestMfaChallenge(selected);
    setBusy(false);
    if (!result.ok) {
      setMessage(result.message);
      return false;
    }
    setChallengeId(result.value.challengeId);
    setMessage("Enter the current code from your authenticator app.");
    return true;
  }, []);

  useEffect(() => {
    if (step !== "challenge" || !configured) return;
    let cancelled = false;
    void (async () => {
      setBusy(true);
      const result = await fetchPendingFactors();
      if (cancelled) return;
      setBusy(false);
      if (!result.ok) {
        if (result.state === "mfa_unconfigured") { setStep("enrollment"); setMessage(result.message); return; }
        if (result.state === "pending_expired" || result.state === "mfa_disabled") {
          setStep("credentials");
        }
        setMessage(result.message);
        return;
      }
      setFactors(result.value);
      const first = result.value[0]?.id ?? "";
      setFactorId(first);
      if (first) await startChallenge(first);
    })();
    return () => {
      cancelled = true;
    };
  }, [step, configured, startChallenge]);

  async function submitCredentials(event: FormEvent) {
    event.preventDefault();
    if (!configured || busy) return;
    setBusy(true);
    setMessage(null);
    let response: Response;
    try {
      response = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });
    } catch {
      setBusy(false);
      setMessage("We couldn’t connect. Please try again.");
      return;
    }
    const body = (await response.json().catch(() => null)) as {
      ok?: boolean;
      state?: string;
      message?: string;
      factors?: unknown;
    } | null;
    setBusy(false);
    if (!response.ok || !body?.ok) {
      if (body?.state === "mfa_setup_required") { setPassword(""); setStep("enrollment"); setMessage(body.message ?? "Set up your authenticator."); return; }
      if (body?.state === "mfa_required") {
        setPassword("");
        setStep("challenge");
        setMessage(body.message ?? "Enter your authenticator code to continue.");
        return;
      }
      setMessage(body?.message ?? "Sign-in failed.");
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  async function submitCode(event: FormEvent) {
    event.preventDefault();
    if (!configured || busy || !factorId || !challengeId || !/^\d{6}$/.test(code)) return;
    setBusy(true);
    setMessage(null);
    const result = await verifyMfa(factorId, challengeId, code);
    setBusy(false);
    if (!result.ok) {
      if (result.state === "pending_expired") {
        setStep("credentials");
      }
      setMessage(result.message);
      setCode("");
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  async function abandon() {
    if (busy) return;
    setBusy(true);
    await cancelMfa();
    setBusy(false);
    setStep("credentials");
    setFactors([]);
    setFactorId("");
    setChallengeId("");
    setCode("");
    setMessage("You can sign in again when you’re ready.");
  }

  return (
    <main className="login">
      <section className="login-brand">
        <img className="auth-logo auth-logo-white" src="/brand/hocalist-wordmark-white.png" alt="Hocalist" width={240} height={80}/>
        <p>Hocalist operations</p>
        <h1>Keep the local marketplace clear, trusted, and moving.</h1>
        <p>
          Review accounts, requests, offers, seller access, and safety reports
          from one focused desktop workspace.
        </p>
        <div className="login-note">
          <strong>Hocalist management</strong>
          <span>{configured ? 'Sign in with your Hocalist account. An authenticator code helps keep your account safe.' : 'Sign-in is temporarily unavailable. Please contact the Hocalist account owner.'}</span>
        </div>
      </section>
      <section className="login-panel">
        <img className="auth-logo auth-logo-mobile" src="/brand/hocalist-wordmark.png" alt="Hocalist" width={200} height={66}/>
        {step === "enrollment" ? <AuthenticatorSetup signedIn onRestart={() => { void abandon(); }} onComplete={() => { router.push("/dashboard"); router.refresh(); }} /> : step === "credentials" ? (
          <form className="login-card" onSubmit={submitCredentials}>
            <div>
              <p className="eyebrow">Management portal</p>
              <h2>Welcome back</h2>
              <p>Authorized administrators only.</p>
            </div>
            <label>
              Email address
              <input
                type="email"
                autoComplete="username"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                disabled={!configured}
                required
              />
            </label>
            <label>
              Password
              <PasswordInput
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                disabled={!configured}
                required
              />
            </label>
            <button className="primary login-button" type="submit" disabled={!configured || busy}>
              {busy ? "Signing in…" : "Sign in"}
            </button>
            <Link href="/reset-password">Forgot password?</Link>
            {message ? <p role="alert">{message}</p> : null}
          </form>
        ) : (
          <form className="login-card" onSubmit={submitCode}>
            <div>
              <p className="eyebrow">Account security</p>
              <h2>Verify it is you</h2>
              <p>
                Enter the six-digit code shown in your authenticator app.
              </p>
            </div>
            {factors.length > 1 ? (
              <label>
                Authenticator app
                <select
                  value={factorId}
                  disabled={busy}
                  onChange={(event) => {
                    setFactorId(event.target.value);
                    void startChallenge(event.target.value);
                  }}
                >
                  {factors.map((factor) => (
                    <option key={factor.id} value={factor.id}>
                      {factor.friendlyName ?? factor.factorType}
                    </option>
                  ))}
                </select>
              </label>
            ) : null}
            <label>
              Six-digit code
              <input
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                placeholder="000000"
                maxLength={6}
                value={code}
                onChange={(event) => setCode(event.target.value.replace(/\D/g, ""))}
                disabled={busy || !challengeId}
                required
              />
            </label>
            <button
              className="primary login-button"
              type="submit"
              disabled={busy || !challengeId || !/^\d{6}$/.test(code)}
            >
              {busy ? "Checking…" : "Verify code"}
            </button>
            <div className="form-actions">
              <button
                type="button"
                disabled={busy || !factorId}
                onClick={() => void startChallenge(factorId)}
              >
                Try again
              </button>
              <button type="button" disabled={busy} onClick={() => void abandon()}>
                Back to sign-in
              </button>
            </div>
            {message ? <p role="alert">{message}</p> : null}
            <small>
              Lost access to your authenticator? Contact the Hocalist account owner for help.
            </small>
          </form>
        )}
      </section>
    </main>
  );
}

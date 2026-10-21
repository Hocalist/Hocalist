import { cookies } from "next/headers";

import { adminMfaPolicy } from "../lib/admin-rules";
import { adminConfig, MFA_PENDING_COOKIE } from "../lib/admin-session";

import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";

export default async function Login() {
  const configured = adminConfig() !== null;
  const policyRequired = adminMfaPolicy(process.env.HOCALIST_ADMIN_MFA) === "required";
  const store = await cookies();
  const pending = Boolean(store.get(MFA_PENDING_COOKIE)?.value);
  return (
    <LoginForm configured={configured} policyRequired={policyRequired} pending={pending} />
  );
}

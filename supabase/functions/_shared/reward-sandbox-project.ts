import { sharedProject, qaAccount } from "./stripe-test-project.ts";

// Bank setup uses the named QA sandbox. Withdrawal dispatch has its own guard.
export function recipientSetupProject(
  env: (name: string) => string | undefined,
) {
  if (env("SUPABASE_URL") === sharedProject &&
      env("HOCALIST_REWARD_SANDBOX_ACCOUNT_ID") === qaAccount) {
    return sharedProject;
  }
  return rewardSandboxProject(env);
}

// Sandbox Stripe payments must never settle withdrawals on the production ledger.
export function rewardSandboxProject(
  env: (name: string) => string | undefined,
) {
  const project = env("SUPABASE_URL");
  if (
    !project || project === sharedProject ||
    project !== env("HOCALIST_REWARD_SANDBOX_PROJECT_URL")
  ) {
    return null;
  }
  return project;
}

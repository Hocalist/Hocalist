import { strictEqual } from "node:assert/strict";
import { recipientSetupProject, rewardSandboxProject } from "./reward-sandbox-project.ts";
import { PROJECT } from "./stripe-test-billing.ts";

Deno.test("bank setup requires the QA sandbox and withdrawal dispatch stays isolated", () => {
  const config: Record<string, string> = {
    SUPABASE_URL: PROJECT,
    HOCALIST_REWARD_SANDBOX_PROJECT_URL: PROJECT,
    HOCALIST_REWARD_SANDBOX_ACCOUNT_ID: "acct_1UZ6RADsZD1mZ3BB",
  };
  const env = (name: string) => config[name];
  strictEqual(recipientSetupProject(env), PROJECT);
  strictEqual(rewardSandboxProject(env), null);
  config.HOCALIST_REWARD_SANDBOX_ACCOUNT_ID = "other";
  strictEqual(recipientSetupProject(env), null);
});

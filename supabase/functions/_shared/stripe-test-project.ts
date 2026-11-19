export const sharedProject = "https://icqwbzswokoulatomgql.supabase.co";
export const sharedBillingAccount = "acct_1Le6hqDmHEV44E5Y";
export const qaAccount = "acct_1UZ6RADsZD1mZ3BB";

export function billingEnvironment(project: string | undefined, account?: string) {
  if (project !== sharedProject) throw new Error("configuration_unavailable");
  if (account === qaAccount) {
    return { project, account, keyName: "HOCALIST_REWARD_STRIPE_SANDBOX_KEY", webhookKey: "HOCALIST_QA_STRIPE_WEBHOOK_SECRET" };
  }
  if (account === undefined || account === sharedBillingAccount) {
    return { project, account: sharedBillingAccount, keyName: "HOCALIST_STRIPE_TEST_API_KEY", webhookKey: "HOCALIST_STRIPE_TEST_WEBHOOK_SECRET" };
  }
  throw new Error("configuration_unavailable");
}

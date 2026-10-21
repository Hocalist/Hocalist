// Browser helper for the reviewed admin RPC bridge.

export type AdminRpcResponse =
  | { ok: true; data: unknown }
  | { ok: false; state?: string; message: string };

export async function adminRpc(
  functionName: string,
  params: Record<string, unknown>,
): Promise<AdminRpcResponse> {
  let response: Response;
  try {
    response = await fetch("/api/admin-rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ function: functionName, params }),
    });
  } catch {
    return { ok: false, message: "The admin backend is unreachable." };
  }
  const body = (await response.json().catch(() => null)) as {
    ok?: boolean;
    data?: unknown;
    state?: string;
    message?: string;
  } | null;
  if (!response.ok || !body?.ok) {
    return {
      ok: false,
      state: body?.state,
      message: body?.message ?? "The admin backend rejected the request.",
    };
  }
  return { ok: true, data: body.data };
}

export function adminCommand(
  operation: string,
  input: Record<string, unknown>,
  key: string = crypto.randomUUID(),
) {
  return adminRpc("marketplace_admin_command", {
    p_operation: operation,
    p_key: key,
    p_input: input,
  });
}

export function creditAdminCommand(
  operation: string,
  input: Record<string, unknown>,
  key: string = crypto.randomUUID(),
) {
  return adminRpc("credit_admin_command", {
    p_operation: operation,
    p_key: key,
    p_input: input,
  });
}

export function trustCommand(
  operation: string,
  input: Record<string, unknown>,
  key: string = crypto.randomUUID(),
) {
  return adminRpc("admin_trust_command", {
    p_operation: operation,
    p_key: key,
    p_input: input,
  });
}

// Revoke the current provider session, including its refresh tokens.
export async function revokeSession(
  config: { url: string; anonKey: string }, accessToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  try {
    const response = await fetchImpl(config.url + '/auth/v1/logout?scope=local', {
      method: 'POST', headers: { apikey: config.anonKey, Authorization: 'Bearer ' + accessToken },
      signal: AbortSignal.timeout(10000),
    });
    return response.ok || response.status === 401;
  } catch { return false; }
}

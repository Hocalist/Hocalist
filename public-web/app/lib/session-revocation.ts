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
    if (response.ok || response.status === 401) return true;
    // A session already removed by Auth has nothing left to revoke. Do not
    // mistake this definitive response for a provider outage.
    if (response.status === 403) {
      const body = await response.json().catch(() => null);
      return body?.code === 'session_not_found';
    }
    return false;
  } catch { return false; }
}

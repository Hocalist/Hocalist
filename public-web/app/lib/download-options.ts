export type DownloadPlatform = 'android' | 'ios';
export function downloadOptions(env: Record<string, string | undefined>) {
  function safe(value: string | undefined, hosts: string[]) {
    try {
      const u = new URL(value ?? '');
      return u.protocol === 'https:' && !u.username && !u.password && hosts.includes(u.hostname) ? u.href : null;
    } catch { return null; }
  }
  const android = safe(env.NEXT_PUBLIC_PLAY_STORE_URL, ['play.google.com']) ??
    safe(env.HOCALIST_ANDROID_TEST_DOWNLOAD_URL, ['hocalist.com', 'www.hocalist.com']);
  const ios = safe(env.NEXT_PUBLIC_APP_STORE_URL, ['apps.apple.com']) ??
    safe(env.HOCALIST_IOS_TESTFLIGHT_URL, ['testflight.apple.com']);
  return { android, ios };
}

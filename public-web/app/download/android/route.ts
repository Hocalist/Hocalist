import { androidTestRelease } from '../../lib/android-test-release';

export function GET() {
  // The APK is a versioned release asset, not a file streamed through Vercel.
  // Keep this address stable for the website and existing waitlist links.
  return new Response(null, {
    status: 307,
    headers: { Location: androidTestRelease.assetUrl, 'Cache-Control': 'no-store' },
  });
}

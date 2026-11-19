# Hocalist Public Web

Public website for Hocalist, including homepage, how it works, seller plans,
safety, support, download, privacy, terms, and refund/cancellation pages.

This app is public-facing. It does not host the mobile app UI or private
management tools, and it does not process buyer-to-seller item payments.

## Commands

```bash
npm install
npm run dev
npm run build
```

## Billing configuration

The authenticated `/billing`, `/billing/return` and `/billing/cancel` pages use
the existing account-bound billing functions. A return URL never grants credits;
the pages read the recorded checkout status.

Set these server environment variables in the hosting project:

- `HOCALIST_SUPABASE_URL`: the approved project URL.
- `HOCALIST_SUPABASE_ANON_KEY`: its public publishable/anon key.
- `HOCALIST_WEBSITE_ORIGIN`: the exact canonical HTTPS website origin used for
  same-origin request validation (currently `https://www.hocalist.com`).
- `HOCALIST_WEBSITE_FUNCTIONS_URL`: optional function base URL override; normally
  omit it to use the configured Supabase project.
- `HOCALIST_WAITLIST_INTAKE_SECRET`: only when the server-controlled waitlist
  intake has been configured with the matching secret.
- `HOCALIST_BILLING_APP_ORIGINS`: optional comma-separated exact HTTPS app
  origins allowed to establish a short-lived billing session and receive the
  Return to app link. Omit this to keep app-session admission disabled; never
  use wildcard domains. Loopback HTTP origins are supported for local testing.

The Flutter web build must separately enable `HOCALIST_BILLING_APP_SESSION`
after the app-session route is deployed and its exact origin is configured.
This transfers only a verified access token by top-level POST, never by URL;
it does not transfer or rotate an app refresh token. Website admission still
requires the matching verified identity and the active-seller/restriction gate.
Native builds continue to use the existing website sign-in path.

## Launch information and feedback

The existing download form collects optional name/city and buyer/seller interest
alongside its consented email signup. The launch section in the existing admin
dashboard shows waitlist leads, download clicks, signed-in first mobile opens
and registrations separately. A download click does not establish an install;
first opens count once per account/platform from the tracking release onward.

Apply `supabase/migrations/20261119092950_buyer_launch_feedback.sql` to the
existing Hocalist database before deploying the new intake/admin code. It keeps
the existing waitlist admission secret, consent checks and support cases.
Feedback screenshots reuse private report evidence and require an admin plus
an exact case/media reference to read them.

The Android test download defaults to `/download/android`, which redirects to
the versioned APK in this repository's GitHub Releases. The release date, size
and SHA-256 live in `app/lib/android-test-release.ts`. Upload and verify the
release asset before changing that metadata. The page identifies it as a test
build; iOS remains unavailable until a real destination is configured.

For early access, `HOCALIST_ANDROID_TEST_DOWNLOAD_URL` may override this with an approved
HTTPS APK on `hocalist.com` or `www.hocalist.com`.
`HOCALIST_IOS_TESTFLIGHT_URL` may point to an existing Apple TestFlight invite.
Official store links take precedence. Missing or invalid links remain marked
unavailable for iOS. An empty Android override disables the test download.
Keep download access independent of waitlist signup.

Keep `HOCALIST_WEBSITE_PREVIEW` unset on the public deployment. Store download
links use `NEXT_PUBLIC_APP_STORE_URL` and `NEXT_PUBLIC_PLAY_STORE_URL` only after
the respective store listing exists. No Stripe secret or service-role key belongs
in the browser or this repository.

The current billing endpoints use Stripe TEST mode. Publishing these routes does
not enable real charges, item payments or payouts. After publishing, verify the
portal return and the exact checkout return/status journey with a test seller.

`npm test` runs the website regressions, including a disposable SQL waitlist
bridge using the repository's bootstrap and waitlist migration files.

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

Keep `HOCALIST_WEBSITE_PREVIEW` unset on the public deployment. Store download
links use `NEXT_PUBLIC_APP_STORE_URL` and `NEXT_PUBLIC_PLAY_STORE_URL` only after
the respective store listing exists. No Stripe secret or service-role key belongs
in the browser or this repository.

The current billing endpoints use Stripe TEST mode. Publishing these routes does
not enable real charges, item payments or payouts. After publishing, verify the
portal return and the exact checkout return/status journey with a test seller.

`npm test` runs the website regressions, including a disposable SQL waitlist
bridge using the repository's bootstrap and waitlist migration files.

# Hocalist transactional emails

Status October 18: all 13 templates published to the approved shared Supabase project and independently reread; all seven security-notification flags remain false. Public white logo verified HTTP 200. One approved controlled recovery email arrived in Gmail Inbox with the fully loaded branded logo and no red warning visible. Sender signing and TLS checked; reset link was not opened. This does not establish universal Gmail warning resolution or other authentication-flow delivery. Generate with `node emails/build.mjs`; validate with `node --test emails/templates.test.mjs`. `preview.html` contains no authentication token. Approved navy #00036c, exact white logo, white content panel, inline styles, presentation tables, system-font fallback and support/privacy links form the shared language. No animation or web-font dependency in email.

## Coverage and provider boundaries

- `manifest.json`: six Supabase authentication templates and seven security notification templates. Keep `{{ .ConfirmationURL }}` / `{{ .Token }}` unchanged; no custom verification endpoint or redirect reconstruction. Security templates do not enable their sending flags.
- Existing source inspection found no SendGrid application-email sender in `supabase/functions`, `public-web`, `scripts` or `database`. Push/in-app notifications are not email delivery. The shell is reusable for future transactional senders, but wiring new email sends is separate work requiring real producer contracts, escaping and delivery proof.
- Stripe receipt/invoice/portal email content is provider-owned. Its branding settings are separate from Supabase templates. Inventory currently enabled provider emails in the dashboard before claiming coverage.
- Supabase Auth is shared with Postaneur. Back up the live subjects/bodies and enabled flags before publishing. The historical owner approved shared Hocalist SMTP, but verify template impact and current configuration before changing shared Auth branding.
- The white logo must be deployed and publicly retrievable over HTTPS at `https://www.hocalist.com/brand/hocalist-wordmark-white.png` before publishing. Local existence is not publication proof. Alt text remains visible with images blocked.

## Gmail warning investigation and release gate

### October 18 dark-mode follow-up

Shared source now protects navy header/button backgrounds using a solid gradient plus colour fallback, with Gmail-scoped blend wrappers for white text and a supporting-client dark content theme. Four tests pass. Independent live reads proved the patch in authentication templates and the first four security notices (indices 0–9 in dashboard order). Follow-up independent live reads confirmed the remaining three notices saved with dark-mode protection; the MFA-method-added body matched the intended source exactly, and its sending flag remained false. All 13 templates are now confirmed persisted with the protection. No security-notification flags changed. Physical Gmail dark-mode verification and fresh-email delivery remain pending; existing received email is immutable.

Historical September 27 evidence: authentication passed SPF/DKIM/DMARC, but Gmail flagged recovery mail even after click tracking was disabled. No root cause or resolution was proved. A prettier template is not proof of remediation.

1. Inspect the affected message and a fresh controlled message in Gmail; record warning wording, timestamp, sender, mailed-by/signed-by and authentication summary. Never store live tokens in tracked files.
2. Inspect current SendGrid domain authentication, sender identity, HTML/plain-text click tracking and open tracking. Check actual message links without opening a one-time action. Compare visible brand with link hosts; no speculative DNS or DMARC policy changes.
3. Check Supabase sender, subjects/bodies, allowed redirects and current Site URL. Preserve shared-app behavior. Compare exact outbound template and actual received message.
4. Review domain/link reputation and provider delivery records. Gmail does not necessarily disclose its classification reason; distinguish hypotheses from confirmed defects. Do not dismiss/report-not-phishing as a substitute for fixing the sender.
5. Publish reviewed templates only after shared impact and hosted logo are verified and live mutation is authorized. Keep existing security notification flags, expiry, confirmation behavior and scopes unchanged.
6. Send only authorized controlled tests: signup, recovery, sign-in and email-change flows. Verify actual link return, mobile email layout, dark mode and images blocked, plus Gmail warning status. No real customer mailing. Security emails can be previewed without generating account mutations solely to trigger them.

References: https://supabase.com/docs/guides/auth/auth-email-templates and https://support.google.com/mail/answer/180707.

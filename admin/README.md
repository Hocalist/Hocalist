# Hocalist Admin Portal

Desktop Next.js workspace with route-backed account, marketplace, moderation, billing, delivery and safety tools. Missing backend configuration displays an unavailable state; it does not grant access.

## Server configuration

| Variable | Purpose |
|---|---|
| HOCALIST_SUPABASE_URL | Hocalist Supabase project URL |
| HOCALIST_SUPABASE_ANON_KEY | Public project key used with the administrator's own authenticated session |
| HOCALIST_ADMIN_MFA | Set to required in every hosted environment |

No service-role key is needed. Sessions use HttpOnly cookies, provider validation and server-side refresh. Logout revokes the current provider session before clearing cookies. Privileged database functions independently enforce administrator membership and AAL2 after enforcement is activated.

## Administrator onboarding

Deploy migration 218 before enabling migration 216. Publish this portal with MFA required before activating enforcement. Initial access-manager provisioning is a reviewed database operation; preserve existing owners. A password-only session can access only its own authenticator eligibility and setup flow, not administrator data. The account owner privately scans the QR code and verifies a code in the portal.

Settings provides an Administrators section. Access managers can add existing, email-verified Hocalist accounts as regular administrators and remove regular administrators. Managers cannot remove themselves or another manager through this section. Changes are audited and retries reuse the same operation key. Newly added accounts must set up MFA before privileged access.

## Verification

Run npm test and npm run build. Local tests and builds do not prove deployed configuration or a real owner's MFA enrolment. Review hosted sign-in, second-factor admission, permissions and logout before release clearance.

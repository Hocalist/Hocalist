# Approved Resign

Owner-approved mobile home page design references and logo source files.

## Upgraded Buyer Replacements — 2026-08-22

The following files are the current authoritative references and supersede their
earlier image contents:

| Route / state | Approved source | Reference viewport | State |
| --- | --- | --- | --- |
| Created-account buyer home | `home-with-created-account-approved-talk-details.png` | 426 × 923 logical pixels | Active request plus upcoming meetings |
| Post product request — details | `post-request-approved/4.2-post-new-request-products-approved.png` | 426 × 923 logical pixels | Product selected, step 1 |
| Post service request — details | `post-request-approved/4.2.1-post-new-request-service-approved.png` | 426 × 922 logical pixels | Service selected, step 1 |
| Offers received | `buyer-request-navigation-approved/5 Offers Received Dashboard-approved.png` | 426 × 923 logical pixels | Two offers, best-match sorting |
| Buyer chat | `offer-chat-approved/6.1 Talk to seller chat-approved.png` | 426 × 922 logical pixels | One active deal with meeting set |

Implementation notes:

- Names, prices, dates, PINs, rewards, locations, and messages are realistic
  reference content, not values to hardcode as business configuration.
- One buyer/seller conversation may contain multiple deal cards. The seller can
  revise a deal from its card; the buyer reviews the changes before accepting.
- After acceptance, the meeting appears in the buyer home `Upcoming meetings`
  section.
- Database persistence, realtime delivery, targeting-credit restoration, and
  reward recalculation are deferred until the Supabase integration.
- Conversation-level three-dot menus contain profile/request access, search,
  mute, safety/help, report, and block. Deal-specific actions stay on deal cards.

## Home Page Design

- `home-page-design/1-home-with-no-account-approved.png`
- `home-page-design/1-1-home-with-no-account-approved.png`

Notes:

- This is the approved home page direction.
- The screen scrolls: the first image is the top of the home page and the second image is the continued scrolled view.
- Current scope is buyer side, but this home page should be shared by buyer and seller.
- UX flow is mostly unchanged unless the owner separately flags UX changes.
- The visible copy is approved, including `Get Paid To Buy`.
- Current implementation priority is buyer. Do not assume the lower seller-side pages are final until more approved designs arrive.
- Bottom navigation labels shown in the reference are approved for the current buyer/no-account home only; do not generalize them to seller pages without later confirmation.
- The FAQ icons/chevrons are interactive controls and should open/close each question.
- The overview video area should look like an embedded YouTube/video player. Use a generated/local placeholder video or video-like poster for now, then replace it when the owner provides the real YouTube link.
- The buyer and seller hero/card people images are not separately available. Try extracting usable crops from the approved screenshots first; if quality is insufficient, create/recreate matching assets with owner approval before implementation.

## Logo Files

- `logos/hocalist-brand-no-background.png`
- `logos/hocalist-brand-squared-background.png`
- `logos/hocalist-brand-circled-background.png`
- `logos/hocalist-logo-with-background.png`
- `logos/hocalist-logo-with-no-background.png`

Notes:

- These are the logo files to use for the upcoming mobile UI design work.
- Do not redraw or reinterpret the logo assets without owner approval.
- Use these logo files in the mobile implementation; do not substitute the older generated/cropped brand files unless explicitly approved.

# Shared UI Element Register

This register is the comparison map for consolidating Buyer and Seller UI
without changing the approved default designs. It classifies every reusable
element family before page-level migration.

## Non-negotiable baseline

- Text scale `1.0` must retain the current approved rendering.
- Shared behavior does not require shared artwork or identical dimensions.
- Seller-approved visuals remain the Seller baseline; Buyer-approved visuals
  remain the Buyer baseline.
- A shared component may expose explicit `buyer` and `seller` variants for
  typography, spacing, icon slots, artwork, color, and geometry.
- Flow-specific compositions stay local when sharing would require enough
  parameters to recreate a page inside a generic widget.
- Every migrated family needs Buyer and Seller proof before another role uses
  it.

## Category A - identical shared foundations

These are global contracts. They must behave identically for both roles and do
not own role-specific artwork or composition.

| Element family | Current source | Shared contract |
| --- | --- | --- |
| Accessibility preferences | `features/accessibility/` and `main.dart` | Text size, font choice, button style, persistence |
| Responsive stages | `theme/responsive_foundation.dart` | Approved, adaptive, and stacked thresholds |
| Approved replica metrics | `features/approved/approved_replica_metrics.dart` | Width classes, bounded geometry, spacing, artwork scale, content width |
| Minimum touch areas | `theme/input_foundation.dart` | Button and input minimum heights and padding |
| Theme-selected font | `theme/hocalist_theme.dart` | Selected family reaches every role unless an approved asset contains text |
| Semantics and focus | Flutter controls and component wrappers | Labels, selected state, button state, keyboard/focus behavior |
| Safe-area/content bounds | responsive page and shell wrappers | Insets, keyboard avoidance, phone/tablet maximum widths |
| Search/select/filter behavior | `theme/control_foundation.dart` | Query, clear, select, checked option, filter state |
| Role asset routing | `theme/role_asset_bundle.dart` | Shared structure may resolve different approved assets by role |

## Category B - shared structures with explicit role variants

These elements are similar in purpose and structure, but their approved Buyer
and Seller visuals are not assumed to be identical.

| Element family | Buyer implementation | Seller implementation | Variant properties that stay explicit |
| --- | --- | --- | --- |
| Top-level header | `BuyerTopLevelHeader` | `SellerAppHeader` | Logo size, role pill, bell artwork, spacing, reflow |
| Nested-page header | `BuyerNestedHeader` and approved page headers | Seller subpage headers | Title alignment, subtitle, side actions, role typography |
| Bottom navigation | `BuyerBottomNavigation` | `SellerBottomNavigation` | Destinations, assets, optical sizes, indicator geometry, labels |
| Primary action | `BuyerPrimaryButton` | `SellerPrimaryButton` | Gradient/accent, approved radius, typography, optional artwork |
| Secondary action | `BuyerSecondaryButton` | `SellerSecondaryButton` | Border/accent, typography, compact geometry |
| Input/textarea | `buyerInputDecoration` | Seller field helpers | Fill, border, label placement, icon slot, role typography |
| Search/filter/sort | Buyer control variant | Seller control variant | Closed-control design and opened-surface accent |
| Icon slot/surface | `BuyerAssetIcon`, `BuyerGlyphIcon` | Seller assets/library glyphs | Asset, optical scale, baked/Flutter surface, stroke treatment |
| Modal/bottom-sheet frame | `BuyerModalSheet` | `SellerModalSheet` | Header artwork, title treatment, padding, role accent |
| Confirmation/information dialog | Buyer upgraded dialog variant | Seller upgraded dialog variant | Role wording, icon, action order and accent |
| Card surface | Buyer approved cards | Seller approved cards | Radius, border, padding, density, role-specific internal layout |
| List/action row | Buyer settings/profile rows | Seller settings/profile rows | Leading artwork, chevron, dividers, type scale |
| Profile summary/avatar | Buyer profile surfaces | Seller profile surfaces | Badges, actions, metadata, avatar treatment |
| Status badge/chip | Buyer offer/deal states | Seller lead/meet states | State color, label, density, icon |
| Tabs/segmented filters | Buyer history/activity tabs | Seller meets/history tabs | Labels, counts, selected treatment, narrow behavior |
| Metric/reward/balance card | Buyer rewards | Seller credits/billing | Content model, colors, illustration, money terminology |
| Alert/notice/banner | Buyer reward/safety/deal notices | Seller targeting/PIN/billing notices | Severity, role accent, artwork, copy |
| Empty/loading/error state | Buyer list destinations | Seller list destinations | Role action, illustration, destination-specific wording |
| Upload/attachment picker | Buyer chat attachment | Seller offer images | Allowed sources, preview, removal, permissions copy |
| Calendar/time control | Buyer meeting details | Seller schedule/reschedule | Available actions, status, role wording |

## Category C - Buyer-only compositions

These remain local compositions while consuming Category A foundations and
Category B variants.

- Logged-out Buyer introduction and benefits.
- Buyer dashboard, rewards, withdrawal, reward history, and buyer deal history.
- Product/service request creation, location, request summary, and updates.
- Offers received, offer detail, seller selection, and Buyer public Seller
  profile.
- Buyer chat deal carousel, deal-details sheets, offer revision acceptance,
  attachments, and conversation options.
- Buyer meeting confirmation, after-meetup, PIN display, review, recovery, and
  support escalation.
- Hocatrends, picked sellers, savings notices, and Buyer notifications.

## Category D - Seller-only compositions

These remain local compositions while consuming Category A foundations and
Category B variants.

- Seller tutorial and Seller dashboard metrics/recommended leads.
- Lead discovery, targeting/credit notices, offer preparation, product image
  upload, location selection, and bid submission.
- Seller chat deal management and revised-offer preparation.
- Seller Meets status tabs, appointment disclosure, PIN entry/verification,
  call/message/reschedule actions.
- Seller profile, verification, original Buyer request, offer history, and
  Buyer public profile.
- Seller credits, billing history, transaction details, and payment methods.
- Seller notifications, notification preferences, safety, help, and support.

## Required states for every reusable family

Each Category B family must be checked in every applicable state rather than
only its default screenshot:

- default, pressed, focused, selected, disabled, and loading;
- empty, error, success, unread, pending, completed, and cancelled;
- short, normal, long, and accessibility-sized text;
- 320, 360, 390, and 430 logical-pixel widths;
- text scales 1.0, 1.15, 1.3, and 1.6;
- Buyer and Seller role variants where both roles consume the family.

## Migration gate

For each Category B family:

1. Capture or measure both current approved role implementations.
2. Record identical structure and intentional role differences.
3. Move only identical behavior into the shared implementation.
4. Express visual differences through named role variants.
5. Prove that the 1.0 rendering did not change for either role.
6. Prove adaptive behavior independently before migrating the next family.

## Accessibility verification - 2026-08-26

- Category A foundations passed their focused default-composition and adaptive
  reflow tests at the approved phone widths.
- Category B representatives passed Buyer and Seller checks for headers,
  navigation, actions, request/offer/chat surfaces, tabs, and account pages.
- Category C Buyer representatives passed narrow dashboard, request, offers,
  chat, Hocatrends, notification, and More-shell checks through `1.6` text
  scale; offers/chat also passed at `2.0`.
- Category D Seller representatives passed the full Seller surface suite at
  320, 360, 390, 430, 768, and 980 logical pixels plus enlarged text.
- The audit found and corrected one local defect: the Seller Meets `Upcoming`
  tab clipped at 320 logical pixels with Extra Large text. Its default approved
  rendering remains unchanged; only narrow accessibility reflow removes the
  decorative calendar icon and assigns tab width by label length.
- Follow-up rendered checks corrected four additional enlarged-text defects
  without changing the approved default layouts: the Buyer home upper section
  now joins the page scroll, the rewards banner contains its copy and artwork,
  Buyer bottom-navigation labels truncate on one line, and chat role badges
  keep their icon and label inline. The Seller tutorial similarly switches to
  whole-page scrolling only when accessibility reflow is active.
- Rendered audit captures were verified locally and remain outside version
  control.

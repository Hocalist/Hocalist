# Buyer Icon System

## Scope

This is the reusable icon contract for every upgraded Buyer page. It applies
to navigation, form, card, header, menu, and action icons. Product photos,
avatars, reward illustrations, decorative art, and semantic status artwork
remain separate because forcing them into an interface-icon treatment would
damage the approved designs.

## Canonical sizes

All values are logical pixels before responsive scaling through
`ApprovedReplicaMetrics.artSize`.

| Role | Slot |
|---|---:|
| Inline metadata | 18 |
| Control/header action | 22 |
| Bottom navigation | 22 |
| Card/form heading | 28 |
| Feature/dashboard action | 40 |
| Hero artwork | 72 |

The slot is the layout contract. The visible artwork is optically centered
inside it. Do not size an icon from the raw PNG dimensions.

## Visual family

- Buyer interface icons use the approved rounded outline family and Buyer blue
  or navy.
- Use one outlined family within a control group. Do not mix filled Material
  glyphs with thin extracted outlines unless the approved screenshot does.
- Green, amber, red, and filled artwork are reserved for semantic status or
  reward meaning.
- Do not add circles, squares, gradients, shadows, or patterned backgrounds
  behind icons unless that treatment is visible in the approved source.
- The dashboard trophy, calendar, plus, and mode artwork have intentional
  approved soft-circle treatments baked into their exact assets. Preserve
  those; do not add another wrapper background.
- A soft circle is not screenshot contamination. When an extracted icon has
  both an approved circle and stray neighbouring pixels, rebuild the clean
  circle at its approved color and remove only the pixels outside it. The
  transparent `dashboard-trophy-glyph.png` variant exists only for surfaces
  that must draw a stronger circle against a lavender parent panel.

## Saved asset sources

| Family | Canonical location | Use |
|---|---|---|
| Shared Buyer navigation | `assets/buyer_nav/` | Home, Hocatrends, Offers, Chats, More |
| Account/home/dashboard | `assets/approved_onboarding_home/` | Header, reward, request, benefit icons |
| Request flow | `assets/post_request/` | Product/service, fields, choices, location, action |
| Offers/chat/deal | `assets/approved_offers_chat/` | Offers, details, active deals, chat and sheets |
| Trends/notifications | `assets/approved_trends_notifications/transparent/` | Transparent outlined Hocatrends and activity icons |

Do not re-extract, redraw, or approximate an icon if the approved asset already
exists in these directories. New approved artwork must be saved in the
appropriate family directory, named by meaning rather than screen position,
and registered in the consuming feature or shared foundation.

Screenshot-extracted icons must be rebuilt before use. Remove neighbouring
text, compression ghosts, patterned pixels, and incomplete background crops;
retain the approved glyph and rebuild only the background treatment shown in
the source. `scripts/normalize_buyer_icon_assets.ps1` performs the color-aware
cleanup for contaminated extracts. `scripts/rebuild_buyer_icon_assets.ps1`
then places every Buyer interface glyph on the same centred 128px canvas while
preserving the approved soft-circle family. Product photos, avatars, logos,
social marks, and decorative illustrations are excluded from that rebuild.

If cleanup cannot preserve the complete approved glyph, stroke, optical center,
and background treatment, do not keep enlarging or masking the screenshot crop.
Rebuild a clean bitmap asset from the approved reference treatment (or use the
matching saved/library glyph), then place the reference and rendered result in
the same comparison image before accepting it.

## Rendering contract

- Use `BuyerAssetIcon` for Buyer bitmap interface icons.
- Use `BuyerIconTokens` for named visual slots.
- Use `BoxFit.contain`; never `cover` for interface icons.
- Do not wrap bitmap icons in `ClipOval` or another crop unless the approved
  source is genuinely circular and the crop has been visually compared.
- Interface source padding is corrected in the saved asset, not by enlarging
  paint beyond the layout slot. `BuyerIconTokens.opticalScaleFor` therefore
  returns `1` for the rebuilt family.
- Rebuilt glyphs keep a transparent safety inset on every edge, preventing
  clipped top/bottom strokes in cards and buttons.
- The Product and Service request tools now share the same canvas, visual fill,
  and optical centre; neither requires a page-specific scale correction.

## Button relationship

Buttons use the global `HocalistButtonTokens` geometry:

- standard primary/secondary minimum height: 48;
- standard horizontal/vertical padding: 16/13;
- compact pill minimum height: 32;
- compact horizontal/vertical padding: 12/7;
- standard radius: 14.
- standard inline button-icon size: 18, centred with standard visual density.

Page-specific screenshot replicas may scale these values but must not silently
fall back to Material defaults.

## Future-screen checklist

1. Open the approved source and identify whether the visual is an interface
   icon, semantic status art, or decorative illustration.
2. Reuse the saved canonical asset when available.
3. Select the named slot by role, not by the raw file size.
4. Compare visible stroke weight, optical center, background treatment, and
   crop against adjacent icons.
5. If extraction remains contaminated or clipped, rebuild the asset and compare
   it directly with the approved source instead of shipping the crop.
6. Check 320, 360, 390, and 430 logical widths before approval.
7. Run both Buyer icon scripts, inspect the generated checkerboard contact
   sheet, and add a focused regression test for any new family rule.

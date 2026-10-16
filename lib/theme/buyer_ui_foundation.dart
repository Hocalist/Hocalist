import '../components/hocalist_reload_link.dart';
import 'package:flutter/material.dart';
import '../components/notification_indicator.dart';
import '../components/hocalist_motion.dart';

import '../features/approved/approved_replica_metrics.dart';
import 'accessibility_visuals.dart';
import 'input_foundation.dart';

/// Shared Buyer colors. Page/flow accents remain explicit variants where the
/// approved screenshots do not support one universal blue or navy.
abstract final class BuyerUiTokens {
  static const text = Color(0xff0c123d);
  static const muted = Color(0xff59617f);
  static const border = Color(0xffe2e4ef);
  static const surface = Colors.white;
  static const softSurface = Color(0xfff1f0ff);
  static const activeSurface = Color(0xffeeedff);
  static const success = Color(0xff109b4e);
  static const successText = Color(0xff087b3b);
  static const rewardGold = Color(0xffffad00);

  static const action = Color(0xff1400c8);
  static const requestAction = Color(0xff1917ff);
  static const offersAction = Color(0xff0f0b7a);
  static const offerChatAction = Color(0xff1117e8);
  static const trendsAction = Color(0xff3518ef);

  static const requestText = Color(0xff10145b);
  static const offerChatText = Color(0xff080b62);
  static const trendsText = Color(0xff0b1047);
}

/// Canonical visual slots for Buyer interface icons.
///
/// These are layout sizes, not raw PNG dimensions. Decorative illustrations,
/// product photos, avatars, and semantic reward/status artwork are deliberately
/// outside this contract.
abstract final class BuyerIconTokens {
  static const double inline = 18;
  static const double control = 22;
  static const double navigation = 22;
  static const double card = 28;
  static const double feature = 40;
  static const double hero = 72;

  /// Buyer icon assets are rebuilt into centred 128px canvases before use, so
  /// the default scale is intentionally uniform. [BuyerAssetIcon.opticalScale]
  /// remains available only for a future approved exception.
  static double opticalScaleFor(String asset) => 1;
}

/// Places supplied Buyer artwork inside a predictable visual slot.
///
/// Approved PNGs are rebuilt into clean, centred canvases by
/// `scripts/rebuild_buyer_icon_assets.ps1`. The optional [opticalScale] is an
/// escape hatch for a future approved exception, not a page-level sizing tool.
class BuyerAssetIcon extends StatelessWidget {
  const BuyerAssetIcon({
    required this.asset,
    required this.slotSize,
    this.opticalScale,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode = BlendMode.srcIn,
    this.semanticLabel,
    super.key,
  });

  final String asset;
  final double slotSize;
  final double? opticalScale;
  final Alignment alignment;
  final Color? color;
  final BlendMode colorBlendMode;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      width: slotSize,
      height: slotSize,
      fit: BoxFit.contain,
      alignment: alignment,
      color: color,
      colorBlendMode: color == null ? null : colorBlendMode,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: semanticLabel == null,
      semanticLabel: semanticLabel,
    );
    final effectiveOpticalScale =
        opticalScale ?? BuyerIconTokens.opticalScaleFor(asset);
    return SizedBox.square(
      key: ValueKey('buyer-icon-slot:$asset'),
      dimension: slotSize,
      child: Align(
        alignment: alignment,
        // Transparent source padding sometimes needs optical enlargement. Do
        // not clip that enlargement back to the raw PNG canvas: doing so cuts
        // top/bottom strokes and makes the same icon look off-centre inside
        // buttons and cards. The layout slot remains fixed; only transparent
        // pixels are allowed to paint outside it.
        child: effectiveOpticalScale == 1
            ? image
            : Transform.scale(
                alignment: alignment,
                scale: effectiveOpticalScale,
                child: image,
              ),
      ),
    );
  }
}

/// Centres library glyphs in the same predictable slots as Buyer bitmap icons.
///
/// Use this for standard actions whose approved reference matches the rounded
/// Material family. Custom approved glyphs continue to use [BuyerAssetIcon].
class BuyerGlyphIcon extends StatelessWidget {
  const BuyerGlyphIcon({
    required this.icon,
    required this.slotSize,
    this.glyphSize,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final double slotSize;
  final double? glyphSize;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: ValueKey('buyer-glyph-slot:${icon.codePoint}'),
      dimension: slotSize,
      child: Center(
        child: Icon(
          icon,
          size: glyphSize ?? slotSize * .82,
          color: color,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

enum BuyerIconSurfaceShape { circle, roundedSquare }

/// A clean, centred background treatment for extracted Buyer glyphs.
///
/// Keep surfaces in Flutter instead of preserving screenshot pixels behind an
/// icon. That prevents compression ghosts and gives circles/squares one shared
/// geometry across cards, buttons, and detail rows.
class BuyerAssetIconSurface extends StatelessWidget {
  const BuyerAssetIconSurface({
    required this.asset,
    required this.surfaceSize,
    required this.iconSize,
    this.backgroundColor = BuyerUiTokens.softSurface,
    this.shape = BuyerIconSurfaceShape.roundedSquare,
    this.radius = 9,
    this.semanticLabel,
    super.key,
  });

  final String asset;
  final double surfaceSize;
  final double iconSize;
  final Color backgroundColor;
  final BuyerIconSurfaceShape shape;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: surfaceSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: shape == BuyerIconSurfaceShape.circle
              ? BoxShape.circle
              : BoxShape.rectangle,
          borderRadius: shape == BuyerIconSurfaceShape.roundedSquare
              ? BorderRadius.circular(radius)
              : null,
        ),
        child: Center(
          child: BuyerAssetIcon(
            asset: asset,
            slotSize: iconSize,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}

/// Canonical chrome for the signed-in top-level Buyer destinations.
///
/// The artwork intentionally uses the current client-requested Hocalist logo.
/// Top-level pages may share this contract without forcing it onto nested
/// pages that correctly use back navigation and a page title.
class BuyerTopLevelHeader extends StatelessWidget {
  const BuyerTopLevelHeader({required this.onNotifications, super.key});

  static const headerKey = ValueKey('buyer-top-level-header');
  static const logoKey = ValueKey('buyer-top-level-header-logo');
  static const modeKey = ValueKey('buyer-top-level-header-mode');
  static const notificationsKey = ValueKey(
    'buyer-top-level-header-notifications',
  );

  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final reflow = metrics.accessibilityReflow;
        final logo = Semantics(
          image: true,
          label: 'Hocalist Reverse Marketplace',
          child: SizedBox(
            key: logoKey,
            width: metrics.artSize(88),
            height: metrics.artSize(54),
            child: Image.asset(
              'assets/brand/hocalist-wordmark.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        );
        final mode = Container(
          key: modeKey,
          constraints: BoxConstraints(minHeight: metrics.geometry(38)),
          padding: EdgeInsets.symmetric(
            horizontal: metrics.geometry(10),
            vertical: metrics.geometry(7),
          ),
          decoration: BoxDecoration(
            color: BuyerUiTokens.softSurface,
            borderRadius: BorderRadius.circular(metrics.geometry(99)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BuyerAssetIcon(
                asset: 'assets/approved_onboarding_home/buyer-mode-check.png',
                slotSize: metrics.artSize(BuyerIconTokens.control),
              ),
              SizedBox(width: metrics.geometry(6)),
              Text(
                'Buyer mode',
                maxLines: 1,
                softWrap: false,
                style: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.badgeStatus,
                  color: BuyerUiTokens.action,
                  weight: FontWeight.w800,
                  height: 1.05,
                ).copyWith(fontSize: metrics.fontSize(12)),
              ),
            ],
          ),
        );
        final notification = Semantics(
          button: true,
          label: 'Notifications',
          child: InkResponse(
            key: notificationsKey,
            onTap: onNotifications,
            radius: metrics.artSize(24),
            child: SizedBox(
              width: metrics.artSize(44),
              height: metrics.artSize(44),
              child: Center(
                child: NotificationArtwork(
                  child: BuyerAssetIcon(
                    asset: 'assets/approved_onboarding_home/notification.png',
                    // Keep the 44px touch target, but match the Seller header's
                    // approved 27px visible bell instead of scaling the raster
                    // artwork to the whole target.
                    slotSize: metrics.artSize(32),
                  ),
                ),
              ),
            ),
          ),
        );

        if (reflow) {
          return Column(
            key: headerKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [logo, const Spacer(), notification]),
              SizedBox(height: metrics.spacing(4)),
              Align(alignment: Alignment.centerRight, child: mode),
            ],
          );
        }

        return SizedBox(
          key: headerKey,
          height: metrics.artSize(54),
          child: Row(
            children: [
              logo,
              const Spacer(),
              mode,
              SizedBox(width: metrics.geometry(8)),
              notification,
            ],
          ),
        );
      },
    );
  }
}

/// Current full-width Buyer action treatment.
///
/// This is the Buyer color variant of the approved Seller primary action:
/// shared 44px geometry, 13px radius, compact type, and a role-specific
/// gradient. Buyer pages should use this instead of local legacy
/// [FilledButton] styles.
class BuyerPrimaryButton extends StatelessWidget {
  const BuyerPrimaryButton({
    required this.label,
    required this.onPressed,
    this.leading,
    this.trailing,
    this.compact = false,
    this.fontSize = 14,
    this.minimumHeight,
    this.colors,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;
  final double fontSize;
  final double? minimumHeight;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final resolvedMinimumHeight = metrics.geometry(
      minimumHeight ?? (compact ? 40 : 44),
    );
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final approvedRadius = metrics.geometry(13);
    final radius = accessibility.radiusOr(approvedRadius);
    final highContrast = accessibility.usesHighContrastButton;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: HocalistPressFeedback(
        enabled: onPressed != null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: resolvedMinimumHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: highContrast
                  ? accessibility.backgroundOr(BuyerUiTokens.action)
                  : null,
              gradient: highContrast
                  ? null
                  : LinearGradient(
                      colors: onPressed == null
                          ? const [Color(0xff9ca3af), Color(0xffb6bcc7)]
                          : colors ??
                                const [
                                  BuyerUiTokens.action,
                                  BuyerUiTokens.requestAction,
                                ],
                    ),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(radius),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.geometry(compact ? 6 : 18),
                    vertical: metrics.geometry(compact ? 7 : 9),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (leading != null) ...[
                        leading!,
                        SizedBox(width: metrics.geometry(compact ? 4 : 10)),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: BuyerTypography.style(
                            context,
                            metrics,
                            BuyerTextRole.buttonLabel,
                            color: accessibility.foregroundOr(Colors.white),
                            weight: FontWeight.w600,
                          ).copyWith(fontSize: metrics.fontSize(fontSize)),
                        ),
                      ),
                      if (trailing != null) ...[
                        SizedBox(width: metrics.geometry(compact ? 2 : 10)),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BuyerSecondaryButton extends StatelessWidget {
  const BuyerSecondaryButton({
    required this.label,
    required this.onPressed,
    this.compact = false,
    this.fontSize = 14,
    this.color = BuyerUiTokens.action,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool compact;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (label.startsWith('Refresh ') || label.startsWith('Reload ')) {
      return Align(
        alignment: Alignment.centerRight,
        child: HocalistReloadLink(
          description: label,
          onPressed: onPressed,
          color: color,
        ),
      );
    }
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final approvedRadius = metrics.geometry(13);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: HocalistPressFeedback(
        enabled: onPressed != null,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            minimumSize: Size.fromHeight(metrics.geometry(compact ? 40 : 44)),
            padding: EdgeInsets.symmetric(
              horizontal: metrics.geometry(compact ? 6 : 18),
              vertical: metrics.geometry(compact ? 7 : 9),
            ),
            side: BorderSide(
              color: accessibility.usesHighContrastButton
                  ? accessibility.buttonBackground
                  : color,
              width: accessibility.usesHighContrastButton
                  ? accessibility.buttonBorderWidth
                  : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                accessibility.radiusOr(approvedRadius),
              ),
            ),
            textStyle: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.buttonLabel,
              weight: FontWeight.w600,
            ).copyWith(fontSize: metrics.fontSize(fontSize)),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Compact nested-page header shared by upgraded Buyer destinations.
///
/// The symmetric 44px side slots preserve a centred 16px page title on narrow
/// phones while keeping the back control comfortably tappable.
class BuyerNestedHeader extends StatelessWidget {
  const BuyerNestedHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.backKey,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Key? backKey;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: metrics.artSize(44),
          child: IconButton(
            key: backKey,
            tooltip: 'Back',
            onPressed: onBack,
            padding: EdgeInsets.zero,
            color: BuyerUiTokens.text,
            icon: BuyerGlyphIcon(
              icon: Icons.arrow_back_rounded,
              slotSize: metrics.artSize(BuyerIconTokens.control),
              glyphSize: metrics.artSize(BuyerIconTokens.control),
            ),
          ),
        ),
        SizedBox(width: metrics.spacing(6)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: metrics.spacing(3)),
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.pageTitle,
                  ),
                ),
                SizedBox(height: metrics.spacing(3)),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.secondaryBody,
                    color: BuyerUiTokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: metrics.spacing(6)),
        SizedBox(width: metrics.artSize(44)),
      ],
    );
  }
}

/// Shared upgraded bottom-sheet shell for Buyer information, forms, menus,
/// confirmations, and pickers.
class BuyerModalSheet extends StatelessWidget {
  const BuyerModalSheet({
    required this.onClose,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.headerArtwork,
    this.iconColor = BuyerUiTokens.action,
    this.iconSurface = BuyerUiTokens.softSurface,
    this.titleKey = const ValueKey('buyer-modal-sheet-title'),
    this.closeKey = const ValueKey('buyer-modal-sheet-close'),
    super.key,
  });

  final VoidCallback onClose;
  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? headerArtwork;
  final Color iconColor;
  final Color iconSurface;
  final Key titleKey;
  final Key closeKey;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final compact = media.size.width < 340;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(metrics.geometry(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * .9),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                metrics.geometry(compact ? 16 : 20),
                metrics.geometry(10),
                metrics.geometry(compact ? 16 : 20),
                metrics.geometry(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: metrics.geometry(52),
                      height: metrics.geometry(5),
                      decoration: BoxDecoration(
                        color: const Color(0xffc8c5d7),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  SizedBox(height: metrics.spacing(10)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null || headerArtwork != null) ...[
                        Container(
                          width: metrics.artSize(34),
                          height: metrics.artSize(34),
                          decoration: BoxDecoration(
                            color: iconSurface,
                            shape: BoxShape.circle,
                          ),
                          child:
                              headerArtwork ??
                              BuyerGlyphIcon(
                                icon: icon!,
                                slotSize: metrics.artSize(18),
                                glyphSize: metrics.artSize(18),
                                color: iconColor,
                              ),
                        ),
                        SizedBox(width: metrics.spacing(10)),
                      ],
                      if (title != null)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: metrics.spacing(1)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title!,
                                  key: titleKey,
                                  style: BuyerTypography.style(
                                    context,
                                    metrics,
                                    BuyerTextRole.pageTitle,
                                    weight: FontWeight.w900,
                                  ),
                                ),
                                if (subtitle != null) ...[
                                  SizedBox(height: metrics.spacing(3)),
                                  Text(
                                    subtitle!,
                                    style:
                                        BuyerTypography.style(
                                          context,
                                          metrics,
                                          BuyerTextRole.secondaryBody,
                                          color: BuyerUiTokens.muted,
                                        ).copyWith(
                                          fontSize: metrics.fontSize(10.75),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      SizedBox(width: metrics.spacing(8)),
                      SizedBox.square(
                        dimension: metrics.artSize(40),
                        child: IconButton(
                          key: closeKey,
                          tooltip: 'Close',
                          onPressed: onClose,
                          padding: EdgeInsets.zero,
                          icon: BuyerGlyphIcon(
                            icon: Icons.close_rounded,
                            slotSize: metrics.artSize(BuyerIconTokens.control),
                            glyphSize: metrics.artSize(BuyerIconTokens.control),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.spacing(title == null ? 4 : 14)),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BuyerFieldLabel extends StatelessWidget {
  const BuyerFieldLabel(this.label, {this.uppercase = false, super.key});

  final String label;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Text(
      uppercase ? label.toUpperCase() : label,
      style: BuyerTypography.style(
        context,
        metrics,
        BuyerTextRole.metadata,
        color: BuyerUiTokens.muted,
        weight: FontWeight.w800,
        letterSpacing: .7,
      ).copyWith(fontSize: metrics.fontSize(10)),
    );
  }
}

/// Input decoration for upgraded Buyer forms and sheets.
InputDecoration buyerInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  String? prefixText,
}) {
  final media = MediaQuery.of(context);
  final metrics =
      ApprovedReplicaScope.maybeOf(context) ??
      ApprovedReplicaMetrics.resolve(
        availableWidth: media.size.width,
        textScaler: media.textScaler,
      );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(metrics.geometry(12)),
    borderSide: const BorderSide(color: BuyerUiTokens.border),
  );
  return InputDecoration(
    isDense: true,
    constraints: BoxConstraints(
      minHeight: metrics.geometry(HocalistInputTokens.minimumHeight),
    ),
    hintText: hintText,
    prefixIcon: prefixIcon,
    prefixText: prefixText,
    filled: true,
    fillColor: const Color(0xfffbfcff),
    contentPadding: metrics.geometryInsets(HocalistInputTokens.contentPadding),
    hintStyle: BuyerTypography.style(
      context,
      metrics,
      BuyerTextRole.secondaryBody,
      color: BuyerUiTokens.muted,
    ),
    enabledBorder: border,
    border: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(12)),
      borderSide: BorderSide(
        color: BuyerUiTokens.action,
        width: metrics.geometry(1.5),
      ),
    ),
  );
}

enum BuyerTextRole {
  displayTitle,
  pageTitle,
  sectionHeading,
  cardTitle,
  primaryBody,
  secondaryBody,
  metadata,
  buttonLabel,
  navigationLabel,
  numericEmphasis,
  badgeStatus,
}

abstract final class BuyerTypography {
  static TextStyle style(
    BuildContext context,
    ApprovedReplicaMetrics metrics,
    BuyerTextRole role, {
    Color? color,
    FontWeight? weight,
    double? height,
    double? letterSpacing,
  }) {
    final spec = _spec(role);
    final theme = Theme.of(context).textTheme;
    final base = switch (role) {
      BuyerTextRole.displayTitle => theme.displaySmall,
      BuyerTextRole.pageTitle => theme.headlineLarge,
      BuyerTextRole.sectionHeading => theme.headlineMedium,
      BuyerTextRole.cardTitle => theme.titleMedium,
      BuyerTextRole.primaryBody => theme.bodyMedium,
      BuyerTextRole.secondaryBody => theme.bodySmall,
      BuyerTextRole.metadata => theme.bodySmall,
      BuyerTextRole.buttonLabel => theme.labelLarge,
      BuyerTextRole.navigationLabel => theme.labelSmall,
      BuyerTextRole.numericEmphasis => theme.headlineMedium,
      BuyerTextRole.badgeStatus => theme.labelSmall,
    };
    return (base ?? const TextStyle()).copyWith(
      color: color ?? spec.color,
      fontSize: metrics.fontSize(spec.size),
      fontWeight: weight ?? spec.weight,
      height: height ?? spec.height,
      letterSpacing: letterSpacing ?? 0,
    );
  }

  static _BuyerTextSpec _spec(BuyerTextRole role) {
    return switch (role) {
      BuyerTextRole.displayTitle => const _BuyerTextSpec(
        size: 20,
        weight: FontWeight.w800,
        height: 1.12,
      ),
      BuyerTextRole.pageTitle => const _BuyerTextSpec(
        size: 16,
        weight: FontWeight.w800,
        height: 1.2,
      ),
      BuyerTextRole.sectionHeading => const _BuyerTextSpec(
        size: 16,
        weight: FontWeight.w800,
        height: 1.2,
      ),
      BuyerTextRole.cardTitle => const _BuyerTextSpec(
        size: 14,
        weight: FontWeight.w800,
        height: 1.22,
      ),
      BuyerTextRole.primaryBody => const _BuyerTextSpec(
        size: 13,
        weight: FontWeight.w500,
        height: 1.38,
      ),
      BuyerTextRole.secondaryBody => const _BuyerTextSpec(
        size: 12,
        weight: FontWeight.w500,
        height: 1.35,
        color: BuyerUiTokens.muted,
      ),
      BuyerTextRole.metadata => const _BuyerTextSpec(
        size: 11,
        weight: FontWeight.w500,
        height: 1.3,
        color: BuyerUiTokens.muted,
      ),
      BuyerTextRole.buttonLabel => const _BuyerTextSpec(
        size: 13,
        weight: FontWeight.w800,
        height: 1.15,
      ),
      BuyerTextRole.navigationLabel => const _BuyerTextSpec(
        size: 10.5,
        weight: FontWeight.w600,
        height: 1.15,
        color: BuyerUiTokens.muted,
      ),
      BuyerTextRole.numericEmphasis => const _BuyerTextSpec(
        size: 20,
        weight: FontWeight.w800,
        height: 1.08,
      ),
      BuyerTextRole.badgeStatus => const _BuyerTextSpec(
        size: 10.5,
        weight: FontWeight.w700,
        height: 1.15,
      ),
    };
  }
}

@immutable
class _BuyerTextSpec {
  const _BuyerTextSpec({
    required this.size,
    required this.weight,
    required this.height,
    this.color = BuyerUiTokens.text,
  });

  final double size;
  final FontWeight weight;
  final double height;
  final Color color;
}

/// Tones for supplemental Buyer state cards (empty, loading, error, success).
enum BuyerNoticeTone { brand, neutral, warning, error, success }

/// Designed Buyer state card for loading, empty, unavailable, error and
/// success states.
///
/// Later-added Buyer panels must use this instead of a bare text stack so every
/// supplemental surface keeps one hierarchy: icon, title, supporting copy and
/// one clear action.
class BuyerStateNotice extends StatelessWidget {
  const BuyerStateNotice({
    required this.icon,
    required this.title,
    this.body,
    this.tone = BuyerNoticeTone.neutral,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.trailing,
    this.detail,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final BuyerNoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final Widget? trailing;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final (background, border, foreground) = switch (tone) {
      BuyerNoticeTone.brand => (
        BuyerUiTokens.softSurface,
        const Color(0xffd9d5ff),
        BuyerUiTokens.action,
      ),
      BuyerNoticeTone.neutral => (
        Colors.white,
        BuyerUiTokens.border,
        BuyerUiTokens.action,
      ),
      BuyerNoticeTone.warning => (
        const Color(0xfffff6e5),
        const Color(0xffffe0a3),
        const Color(0xffb56200),
      ),
      BuyerNoticeTone.error => (
        const Color(0xffffeef0),
        const Color(0xffffc9cf),
        const Color(0xffc62828),
      ),
      BuyerNoticeTone.success => (
        const Color(0xffecf8ee),
        const Color(0xffbfe6c8),
        BuyerUiTokens.successText,
      ),
    };
    final narrow = metrics.availableWidth < 340;
    return HocalistStateTransition(
      stateKey: (title, body, tone, actionLabel),
      child: AnimatedContainer(
        duration: HocalistMotion.duration(context, 160),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: metrics.geometryInsets(EdgeInsets.all(narrow ? 12 : 14)),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(metrics.geometry(16)),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: metrics.artSize(34),
                  height: metrics.artSize(34),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: border),
                  ),
                  child: Center(
                    child: BuyerGlyphIcon(
                      icon: icon,
                      slotSize: metrics.artSize(18),
                      glyphSize: metrics.artSize(18),
                      color: foreground,
                    ),
                  ),
                ),
                SizedBox(width: metrics.spacing(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.cardTitle,
                          weight: FontWeight.w800,
                        ).copyWith(fontSize: metrics.fontSize(13.5)),
                      ),
                      if (body != null) ...[
                        SizedBox(height: metrics.spacing(4)),
                        Text(
                          body!,
                          style: BuyerTypography.style(
                            context,
                            metrics,
                            BuyerTextRole.secondaryBody,
                            color: BuyerUiTokens.muted,
                          ),
                        ),
                      ],
                      if (detail != null) ...[
                        SizedBox(height: metrics.spacing(8)),
                        detail!,
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: metrics.spacing(8)),
                  trailing!,
                ],
              ],
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: metrics.spacing(10)),
              BuyerSecondaryButton(
                key: actionKey,
                label: actionLabel!,
                onPressed: onAction,
                compact: true,
                color: foreground,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small designed status/selection pill for supplemental Buyer surfaces.
class BuyerStatusChip extends StatelessWidget {
  const BuyerStatusChip({
    required this.label,
    this.icon,
    this.tone = BuyerNoticeTone.neutral,
    this.selected = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final BuyerNoticeTone tone;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final (background, border, foreground) = switch (tone) {
      BuyerNoticeTone.brand => (
        BuyerUiTokens.activeSurface,
        const Color(0xffd9d5ff),
        BuyerUiTokens.action,
      ),
      BuyerNoticeTone.neutral => (
        const Color(0xfff7f7fb),
        BuyerUiTokens.border,
        BuyerUiTokens.muted,
      ),
      BuyerNoticeTone.warning => (
        const Color(0xfffff6e5),
        const Color(0xffffe0a3),
        const Color(0xffb56200),
      ),
      BuyerNoticeTone.error => (
        const Color(0xffffeef0),
        const Color(0xffffc9cf),
        const Color(0xffc62828),
      ),
      BuyerNoticeTone.success => (
        const Color(0xffecf8ee),
        const Color(0xffbfe6c8),
        BuyerUiTokens.successText,
      ),
    };
    return Semantics(
      label: label,
      container: true,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: HocalistMotion.duration(context, 160),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(minHeight: metrics.geometry(24)),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.spacing(9),
          vertical: metrics.spacing(4),
        ),
        decoration: BoxDecoration(
          color: selected ? BuyerUiTokens.activeSurface : background,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? BuyerUiTokens.action : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: metrics.artSize(13),
                color: selected ? BuyerUiTokens.action : foreground,
              ),
              SizedBox(width: metrics.spacing(4)),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.badgeStatus,
                  color: selected ? BuyerUiTokens.action : foreground,
                  weight: FontWeight.w800,
                ).copyWith(fontSize: metrics.fontSize(10.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label/value tile used by Buyer balance and summary cards.
class BuyerMetricTile extends StatelessWidget {
  const BuyerMetricTile({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueKey,
    this.tone = BuyerNoticeTone.neutral,
    super.key,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Key? valueKey;
  final BuyerNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final valueColor = switch (tone) {
      BuyerNoticeTone.error => const Color(0xffc62828),
      BuyerNoticeTone.warning => const Color(0xffb56200),
      BuyerNoticeTone.success => BuyerUiTokens.successText,
      _ => BuyerUiTokens.text,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: BuyerTypography.style(
            context,
            metrics,
            BuyerTextRole.metadata,
            color: BuyerUiTokens.muted,
            weight: FontWeight.w800,
            letterSpacing: .6,
          ).copyWith(fontSize: metrics.fontSize(9.5)),
        ),
        SizedBox(height: metrics.spacing(2)),
        Text(
          value,
          key: valueKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              BuyerTypography.style(
                context,
                metrics,
                emphasized
                    ? BuyerTextRole.numericEmphasis
                    : BuyerTextRole.cardTitle,
                color: valueColor,
              ).copyWith(
                fontSize: metrics.fontSize(emphasized ? 20 : 13),
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

/// Section heading with optional trailing action for supplemental panels.
class BuyerSectionHeading extends StatelessWidget {
  const BuyerSectionHeading({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.spacing(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: BuyerTypography.style(
                context,
                metrics,
                BuyerTextRole.sectionHeading,
                weight: FontWeight.w900,
              ).copyWith(fontSize: metrics.fontSize(14.5)),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              key: actionKey,
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: BuyerUiTokens.action,
                padding: EdgeInsets.symmetric(horizontal: metrics.spacing(8)),
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
                textStyle: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.buttonLabel,
                  color: BuyerUiTokens.action,
                ).copyWith(fontSize: metrics.fontSize(12)),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Designed busy strip for supplemental Buyer panels.
class BuyerProgressStrip extends StatelessWidget {
  const BuyerProgressStrip({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.metadata,
              color: BuyerUiTokens.action,
              weight: FontWeight.w700,
            ),
          ),
          SizedBox(height: metrics.spacing(6)),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Semantics(
            container: true,
            label: 'Loading',
            child: LinearProgressIndicator(
              minHeight: metrics.geometry(5),
              backgroundColor: BuyerUiTokens.softSurface,
              valueColor: const AlwaysStoppedAnimation<Color>(
                BuyerUiTokens.action,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

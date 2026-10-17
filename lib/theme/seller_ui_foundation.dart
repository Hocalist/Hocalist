import '../components/hocalist_reload_link.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../components/hocalist_motion.dart';

import '../features/approved/approved_replica_metrics.dart';
import 'accessibility_visuals.dart';
import 'adaptive_palette.dart';

export '../features/approved/approved_replica_metrics.dart';

/// Seller-only visual tokens and responsive helpers for approved Seller UI.
///
/// These values deliberately do not modify the Buyer foundation. Approved
/// Seller screens may use distinct component variants when their references
/// differ.
abstract final class SellerUiColors {
  static const ink = Color(0xFF080B39);
  static const body = Color(0xFF27396F);
  static const primary = Color(0xFF1717D5);
  static const primaryBright = Color(0xFF2915F4);
  static const lavender = Color(0xFFF4F2FF);
  static const lavenderBorder = Color(0xFFE0DEFF);
  static const green = Color(0xFF119527);
  static const greenText = Color(0xFF087A20);
  static const greenSurface = Color(0xFFECF8EE);
  static const amber = Color(0xFFFF9D00);
  static const amberSurface = Color(0xFFFFF6E5);
  static const red = Color(0xFFEF1F29);
  static const redSurface = Color(0xFFFFECEE);
  static const line = Color(0xFFE8EAF2);
  static const muted = Color(0xFF66729A);
  static const white = Color(0xFFFFFFFF);
}

abstract final class SellerAssets {
  static const _root = 'assets/approved_seller';

  static const tutorialPortrait = '$_root/tutorial-portrait.png';
  static const tutorialVideo = '$_root/tutorial-video.png';
  static const tutorialTarget = '$_root/tutorial-benefit-target.png';
  static const tutorialBuyer = '$_root/tutorial-benefit-buyer.png';
  static const tutorialGrowth = '$_root/tutorial-benefit-growth.png';
  static const tutorialValue = '$_root/tutorial-benefit-value.png';
  static const tutorialShield = '$_root/tutorial-fairness-shield.png';

  static const brandWordmark = 'assets/brand/hocalist-wordmark.png';
  static const homeAvatar = '$_root/home-seller-avatar.png';
  static const homeHero = '$_root/home-hero-art.png';
  static const homeTarget = '$_root/home-metric-target.png';
  static const homeDeals = '$_root/home-metric-deals.png';
  static const homeFindBuyers = '$_root/home-find-buyers.png';
  static const homePressureWashing = '$_root/home-pressure-washing.png';
  static const homeRoofRepair = '$_root/home-roof-repair.png';
  static const homeGamingPc = '$_root/home-gaming-pc.png';

  static const navLeads = '$_root/nav/seller-nav-leads.png';
  static const navMeets = '$_root/nav/seller-nav-meets.png';
  static const navChats = '$_root/nav/seller-nav-chats.png';
  static const navHome = '$_root/nav/seller-nav-home.png';
  static const navMore = '$_root/nav/seller-nav-more.png';
}

TextStyle sellerText(
  ApprovedReplicaMetrics metrics,
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = SellerUiColors.ink,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: metrics.fontSize(size),
    fontWeight: weight,
    color: HocalistPalette.textFor(metrics.brightness, color),
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// Shared Seller form typography. Keeping this Seller-scoped prevents the
/// approved Buyer surfaces from inheriting Seller field sizing.
TextStyle sellerInputText(
  ApprovedReplicaMetrics metrics, {
  double size = 13,
  FontWeight weight = FontWeight.w600,
}) {
  return sellerText(metrics, size, weight: weight, height: 1.35);
}

TextStyle sellerInputPlaceholder(
  ApprovedReplicaMetrics metrics, {
  double size = 13,
}) {
  return sellerText(metrics, size, color: SellerUiColors.muted, height: 1.35);
}

/// Input decoration for supplemental Seller forms and sheets.
InputDecoration sellerInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  String? labelText,
}) {
  final media = MediaQuery.of(context);
  final metrics =
      ApprovedReplicaScope.maybeOf(context) ??
      ApprovedReplicaMetrics.resolve(
        brightness: Theme.of(context).brightness,
        availableWidth: media.size.width,
        textScaler: media.textScaler,
      );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(metrics.geometry(12)),
    borderSide: BorderSide(
      color: HocalistPalette.border(context, SellerUiColors.lavenderBorder),
    ),
  );
  return InputDecoration(
    isDense: true,
    constraints: BoxConstraints(minHeight: metrics.geometry(44)),
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: HocalistPalette.surface(context, SellerUiColors.lavender),
    contentPadding: metrics.geometryInsets(
      const EdgeInsets.fromLTRB(14, 12, 14, 12),
    ),
    hintStyle: sellerInputPlaceholder(metrics),
    labelStyle: sellerText(
      metrics,
      12.5,
      weight: FontWeight.w600,
      color: SellerUiColors.body,
    ),
    enabledBorder: border,
    border: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(metrics.geometry(12)),
      borderSide: BorderSide(
        color: HocalistPalette.border(context, SellerUiColors.primaryBright),
        width: metrics.geometry(1.5),
      ),
    ),
  );
}

class SellerResponsivePage extends StatelessWidget {
  const SellerResponsivePage({
    required this.builder,
    this.maxContentWidth = ApprovedReplicaMetrics.tabletContentMaxWidth,
    this.backgroundColor = SellerUiColors.white,
    super.key,
  });

  final Widget Function(BuildContext context, ApprovedReplicaMetrics metrics)
  builder;
  final double maxContentWidth;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HocalistPalette.surface(context, backgroundColor),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = math.min(
              constraints.maxWidth,
              ApprovedReplicaMetrics.supportedViewportMaxWidth,
            );
            final metrics = ApprovedReplicaMetrics.resolve(
              brightness: Theme.of(context).brightness,
              availableWidth: availableWidth,
              textScaler: MediaQuery.textScalerOf(context),
            );
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(maxContentWidth, metrics.contentMaxWidth),
                ),
                child: ApprovedReplicaScope(
                  metrics: metrics,
                  child: builder(context, metrics),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SellerPrimaryButton extends StatelessWidget {
  const SellerPrimaryButton({
    required this.label,
    required this.onPressed,
    this.leading,
    this.trailing,
    this.fontSize = 14,
    this.compact = false,
    this.minimumHeight,
    this.colors,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final double fontSize;
  final bool compact;
  final double? minimumHeight;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final resolvedMinimumHeight = metrics.geometry(
      minimumHeight ?? (compact ? 40 : 44),
    );
    final verticalPadding = metrics.geometry(compact ? 7 : 9);
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
              color: HocalistPalette.surfaceOrNull(
                context,
                highContrast
                    ? accessibility.backgroundOr(SellerUiColors.primary)
                    : null,
              ),
              gradient: highContrast
                  ? null
                  : LinearGradient(
                      colors: onPressed == null
                          ? const [Color(0xFF9CA3AF), Color(0xFFB6BCC7)]
                          : colors ??
                                const [
                                  SellerUiColors.primary,
                                  SellerUiColors.primaryBright,
                                ],
                    ),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Material(
              color: HocalistPalette.surface(context, Colors.transparent),
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(radius),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.geometry(compact ? 6 : 18),
                    vertical: verticalPadding,
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
                          style: sellerText(
                            metrics,
                            fontSize,
                            weight: FontWeight.w600,
                            color: accessibility.foregroundOr(
                              SellerUiColors.white,
                            ),
                          ),
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

class SellerSecondaryButton extends StatelessWidget {
  const SellerSecondaryButton({
    required this.label,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (label.startsWith('Refresh ') || label.startsWith('Reload ')) {
      return Align(
        alignment: Alignment.centerRight,
        child: HocalistReloadLink(
          description: label,
          onPressed: onPressed,
          color: SellerUiColors.primaryBright,
        ),
      );
    }
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
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
            foregroundColor: HocalistPalette.text(
              context,
              SellerUiColors.primaryBright,
            ),
            minimumSize: Size.fromHeight(metrics.geometry(compact ? 40 : 44)),
            padding: EdgeInsets.symmetric(
              horizontal: metrics.geometry(compact ? 6 : 18),
              vertical: metrics.geometry(compact ? 7 : 9),
            ),
            side: BorderSide(
              color: HocalistPalette.border(
                context,
                accessibility.usesHighContrastButton
                    ? accessibility.buttonBackground
                    : SellerUiColors.primaryBright,
              ),
              width: accessibility.usesHighContrastButton
                  ? accessibility.buttonBorderWidth
                  : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                accessibility.radiusOr(approvedRadius),
              ),
            ),
            textStyle:
                (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
                    .copyWith(
                      fontSize: metrics.fontSize(14),
                      fontWeight: FontWeight.w600,
                    ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// Shared upgraded bottom-sheet shell for Seller information, forms, menus,
/// confirmations, and pickers.
class SellerModalSheet extends StatelessWidget {
  const SellerModalSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.child,
    this.accentColor = SellerUiColors.primaryBright,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Widget child;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 340;
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Material(
          color: HocalistPalette.surface(context, SellerUiColors.white),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(metrics.geometry(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * .9),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                metrics.geometry(compact ? 16 : 18),
                metrics.geometry(10),
                metrics.geometry(compact ? 16 : 18),
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
                        color: HocalistPalette.surface(
                          context,
                          const Color(0xffc6c1dd),
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  SizedBox(height: metrics.spacing(10)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: metrics.artSize(34),
                        height: metrics.artSize(34),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            SellerUiColors.lavender,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: metrics.artSize(18),
                          color: HocalistPalette.text(context, accentColor),
                        ),
                      ),
                      SizedBox(width: metrics.spacing(10)),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: metrics.spacing(1)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                key: const Key('sellerActionSheetTitle'),
                                style: sellerText(
                                  metrics,
                                  16,
                                  weight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: metrics.spacing(3)),
                              Text(
                                subtitle,
                                style: sellerText(
                                  metrics,
                                  10.75,
                                  color: SellerUiColors.muted,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: metrics.spacing(8)),
                      SizedBox.square(
                        dimension: metrics.artSize(40),
                        child: IconButton(
                          tooltip: 'Close',
                          onPressed: onClose,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.close_rounded,
                            size: metrics.artSize(22),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: metrics.spacing(14)),
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

/// Tones for supplemental Seller state cards (empty, loading, error, success).
enum SellerNoticeTone { brand, neutral, warning, error, success }

/// Designed Seller state card for loading, empty, unavailable, error and
/// success states.
///
/// Later-added Seller panels must use this instead of a bare text stack so every
/// supplemental surface keeps one hierarchy: icon, title, supporting copy and
/// one clear action.
class SellerStateNotice extends StatelessWidget {
  const SellerStateNotice({
    required this.icon,
    required this.title,
    this.body,
    this.tone = SellerNoticeTone.neutral,
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
  final SellerNoticeTone tone;
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
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final (background, border, foreground) = switch (tone) {
      SellerNoticeTone.brand => (
        SellerUiColors.lavender,
        SellerUiColors.lavenderBorder,
        SellerUiColors.primary,
      ),
      SellerNoticeTone.neutral => (
        SellerUiColors.white,
        SellerUiColors.line,
        SellerUiColors.primary,
      ),
      SellerNoticeTone.warning => (
        SellerUiColors.amberSurface,
        SellerUiColors.amber,
        SellerUiColors.ink,
      ),
      SellerNoticeTone.error => (
        SellerUiColors.redSurface,
        SellerUiColors.red,
        SellerUiColors.red,
      ),
      SellerNoticeTone.success => (
        SellerUiColors.greenSurface,
        SellerUiColors.green,
        SellerUiColors.greenText,
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
          color: HocalistPalette.surface(context, background),
          borderRadius: BorderRadius.circular(metrics.geometry(14)),
          border: Border.all(color: HocalistPalette.border(context, border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: metrics.artSize(32),
                  height: metrics.artSize(32),
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(
                      context,
                      SellerUiColors.white,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: HocalistPalette.border(context, border),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: metrics.artSize(17),
                      color: HocalistPalette.text(context, foreground),
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
                        style: sellerText(
                          metrics,
                          13.5,
                          weight: FontWeight.w800,
                          color: SellerUiColors.ink,
                        ),
                      ),
                      if (body != null) ...[
                        SizedBox(height: metrics.spacing(4)),
                        Text(
                          body!,
                          style: sellerText(
                            metrics,
                            12,
                            color: SellerUiColors.body,
                            height: 1.35,
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
              SellerSecondaryButton(
                key: actionKey,
                label: actionLabel!,
                onPressed: onAction,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small designed status/selection pill for supplemental Seller surfaces.
class SellerStatusChip extends StatelessWidget {
  const SellerStatusChip({
    required this.label,
    this.icon,
    this.tone = SellerNoticeTone.neutral,
    this.selected = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final SellerNoticeTone tone;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final (background, border, foreground) = switch (tone) {
      SellerNoticeTone.brand => (
        SellerUiColors.lavender,
        SellerUiColors.lavenderBorder,
        SellerUiColors.primary,
      ),
      SellerNoticeTone.neutral => (
        SellerUiColors.white,
        SellerUiColors.line,
        SellerUiColors.muted,
      ),
      SellerNoticeTone.warning => (
        SellerUiColors.amberSurface,
        SellerUiColors.amber,
        SellerUiColors.ink,
      ),
      SellerNoticeTone.error => (
        SellerUiColors.redSurface,
        SellerUiColors.red,
        SellerUiColors.red,
      ),
      SellerNoticeTone.success => (
        SellerUiColors.greenSurface,
        SellerUiColors.green,
        SellerUiColors.greenText,
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
          color: HocalistPalette.surface(
            context,
            selected ? SellerUiColors.lavender : background,
          ),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: HocalistPalette.border(
              context,
              selected ? SellerUiColors.primaryBright : border,
            ),
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
                color: HocalistPalette.text(
                  context,
                  selected ? SellerUiColors.primaryBright : foreground,
                ),
              ),
              SizedBox(width: metrics.spacing(4)),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sellerText(
                  metrics,
                  10.5,
                  weight: FontWeight.w800,
                  color: selected ? SellerUiColors.primaryBright : foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label/value tile used by Seller balance and summary cards.
class SellerMetricTile extends StatelessWidget {
  const SellerMetricTile({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueKey,
    this.tone = SellerNoticeTone.neutral,
    super.key,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Key? valueKey;
  final SellerNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final valueColor = switch (tone) {
      SellerNoticeTone.error => SellerUiColors.red,
      SellerNoticeTone.success => SellerUiColors.greenText,
      SellerNoticeTone.warning => SellerUiColors.ink,
      _ => SellerUiColors.ink,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: sellerText(
            metrics,
            9.5,
            weight: FontWeight.w800,
            color: SellerUiColors.muted,
            letterSpacing: .6,
          ),
        ),
        SizedBox(height: metrics.spacing(2)),
        Text(
          value,
          key: valueKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sellerText(
            metrics,
            emphasized ? 20 : 13,
            weight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Section heading with optional trailing action for supplemental panels.
class SellerSectionHeading extends StatelessWidget {
  const SellerSectionHeading({
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
          brightness: Theme.of(context).brightness,
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
              style: sellerText(
                metrics,
                14.5,
                weight: FontWeight.w900,
                color: SellerUiColors.ink,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              key: actionKey,
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: HocalistPalette.text(
                  context,
                  SellerUiColors.primaryBright,
                ),
                padding: EdgeInsets.symmetric(horizontal: metrics.spacing(8)),
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
                textStyle: sellerText(
                  metrics,
                  12,
                  weight: FontWeight.w800,
                  color: SellerUiColors.primaryBright,
                ).copyWith(fontFamily: 'Nunito'),
              ),
              child: Text(
                actionLabel!,
                style: sellerText(
                  metrics,
                  12,
                  weight: FontWeight.w800,
                  color: SellerUiColors.primaryBright,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Designed busy strip for supplemental Seller panels.
class SellerProgressStrip extends StatelessWidget {
  const SellerProgressStrip({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: sellerText(
              metrics,
              11,
              weight: FontWeight.w700,
              color: SellerUiColors.primary,
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
              backgroundColor: HocalistPalette.surface(
                context,
                SellerUiColors.lavender,
              ),
              valueColor: const AlwaysStoppedAnimation<Color>(
                SellerUiColors.primaryBright,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

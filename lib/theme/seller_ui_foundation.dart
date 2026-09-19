import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../features/approved/approved_replica_metrics.dart';
import 'accessibility_visuals.dart';

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
    color: color,
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
      color: backgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = math.min(
              constraints.maxWidth,
              ApprovedReplicaMetrics.supportedViewportMaxWidth,
            );
            final metrics = ApprovedReplicaMetrics.resolve(
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
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: resolvedMinimumHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highContrast
              ? accessibility.backgroundOr(SellerUiColors.primary)
              : null,
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
          color: Colors.transparent,
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
                        color: accessibility.foregroundOr(SellerUiColors.white),
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
    final media = MediaQuery.of(context);
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final approvedRadius = metrics.geometry(13);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: SellerUiColors.primaryBright,
        minimumSize: Size.fromHeight(metrics.geometry(compact ? 40 : 44)),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.geometry(compact ? 6 : 18),
          vertical: metrics.geometry(compact ? 7 : 9),
        ),
        side: BorderSide(
          color: accessibility.usesHighContrastButton
              ? accessibility.buttonBackground
              : SellerUiColors.primaryBright,
          width: accessibility.usesHighContrastButton
              ? accessibility.buttonBorderWidth
              : 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            accessibility.radiusOr(approvedRadius),
          ),
        ),
        textStyle: sellerText(metrics, 14, weight: FontWeight.w600),
      ),
      child: Text(label),
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
          availableWidth: media.size.width,
          textScaler: media.textScaler,
        );
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Material(
          color: SellerUiColors.white,
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
                        color: const Color(0xffc6c1dd),
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
                        decoration: const BoxDecoration(
                          color: SellerUiColors.lavender,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: metrics.artSize(18),
                          color: accentColor,
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

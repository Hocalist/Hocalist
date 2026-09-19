import 'package:flutter/foundation.dart';

/// Global accessibility layout stages shared by Buyer and Seller surfaces.
///
/// Text may scale independently at every stage. The stage only describes how
/// much structural adaptation a component is allowed to use:
///
/// * [approved] keeps the approved composition and geometry.
/// * [adaptive] permits local wrapping/growth where measured space is tight.
/// * [stacked] permits a component to stack its own children as a last resort.
enum HocalistAccessibilityLayout { approved, adaptive, stacked }

/// Shared responsive policy for the mobile application.
///
/// These thresholds deliberately avoid treating any scale above 1.0 as a
/// reason to redesign a whole page. Individual components still own their
/// role-specific visual variants and may adapt earlier when real constraints
/// prove that their content no longer fits.
abstract final class HocalistResponsivePolicy {
  static const double approvedTextScaleMax = 1.15;
  static const double stackedTextScaleMin = 1.6;

  static HocalistAccessibilityLayout accessibilityLayoutFor(double textScale) {
    if (textScale <= approvedTextScaleMax) {
      return HocalistAccessibilityLayout.approved;
    }
    if (textScale < stackedTextScaleMin) {
      return HocalistAccessibilityLayout.adaptive;
    }
    return HocalistAccessibilityLayout.stacked;
  }

  static bool shouldStack({
    required HocalistAccessibilityLayout layout,
    required double availableWidth,
    required double adaptiveMinimumWidth,
  }) {
    return layout == HocalistAccessibilityLayout.stacked ||
        (layout == HocalistAccessibilityLayout.adaptive &&
            availableWidth < adaptiveMinimumWidth);
  }
}

@immutable
class HocalistResponsiveSnapshot {
  const HocalistResponsiveSnapshot({
    required this.availableWidth,
    required this.textScale,
    required this.accessibilityLayout,
  });

  factory HocalistResponsiveSnapshot.resolve({
    required double availableWidth,
    required double textScale,
  }) {
    return HocalistResponsiveSnapshot(
      availableWidth: availableWidth,
      textScale: textScale,
      accessibilityLayout: HocalistResponsivePolicy.accessibilityLayoutFor(
        textScale,
      ),
    );
  }

  final double availableWidth;
  final double textScale;
  final HocalistAccessibilityLayout accessibilityLayout;

  bool get preservesApprovedComposition =>
      accessibilityLayout == HocalistAccessibilityLayout.approved;
  bool get permitsLocalReflow =>
      accessibilityLayout != HocalistAccessibilityLayout.approved;
  bool get permitsStacking =>
      accessibilityLayout == HocalistAccessibilityLayout.stacked;
}

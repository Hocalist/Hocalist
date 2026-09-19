import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/responsive_foundation.dart';

enum ApprovedReplicaWidthClass { narrow320, compact360, reference, tablet }

@immutable
class ApprovedReplicaMetrics {
  const ApprovedReplicaMetrics._({
    required this.availableWidth,
    required this.textScale,
    required this.widthClass,
    required this.geometryScale,
    required this.typographyScale,
    required this.contentMaxWidth,
    required this.accessibilityLayout,
    required this.accessibilityReflow,
  });

  static const double referenceCanvasWidth = 390;
  static const double referencePhoneMaxWidth = 430;
  static const double tabletBreakpoint = 600;
  static const double supportedViewportMaxWidth = 980;
  static const double tabletContentMaxWidth = 920;
  static const double tabletTypographyScale = 1.06;
  static const double narrowScale = 320 / referenceCanvasWidth;
  static const double compactScale = 360 / referenceCanvasWidth;

  factory ApprovedReplicaMetrics.resolve({
    required double availableWidth,
    required TextScaler textScaler,
  }) {
    assert(availableWidth >= 0);
    final textScale = textScaler.scale(1);
    final responsive = HocalistResponsiveSnapshot.resolve(
      availableWidth: availableWidth,
      textScale: textScale,
    );
    final accessibilityReflow = responsive.permitsLocalReflow;
    final widthClass = switch (availableWidth) {
      < 340 => ApprovedReplicaWidthClass.narrow320,
      < 390 => ApprovedReplicaWidthClass.compact360,
      < tabletBreakpoint => ApprovedReplicaWidthClass.reference,
      _ => ApprovedReplicaWidthClass.tablet,
    };
    // Preserve the approved 390px composition at every phone width. Using a
    // fixed 320/360 bucket made in-between and sub-320 browser widths render
    // wider than their viewport, which is what produced the owner-reported
    // clipping and overflow strips.
    final lockedScale = availableWidth < referenceCanvasWidth
        ? availableWidth / referenceCanvasWidth
        : 1.0;
    // Text size must not reset every card, icon, radius, and spacing value.
    // Phone geometry continues to follow the approved 390px composition while
    // text is allowed to scale and individual components adapt locally.
    final geometryScale = lockedScale;
    final expansionProgress = _progress(
      availableWidth,
      referencePhoneMaxWidth,
      supportedViewportMaxWidth,
    );
    final typographyScale = accessibilityReflow
        ? 1.0
        : availableWidth < referenceCanvasWidth
        ? lockedScale
        : _lerp(1, tabletTypographyScale, expansionProgress);
    final contentMaxWidth = math.min(availableWidth, tabletContentMaxWidth);

    return ApprovedReplicaMetrics._(
      availableWidth: availableWidth,
      textScale: textScale,
      widthClass: widthClass,
      geometryScale: geometryScale,
      typographyScale: typographyScale,
      contentMaxWidth: contentMaxWidth,
      accessibilityLayout: responsive.accessibilityLayout,
      accessibilityReflow: accessibilityReflow,
    );
  }

  final double availableWidth;
  final double textScale;
  final ApprovedReplicaWidthClass widthClass;
  final double geometryScale;
  final double typographyScale;
  final double contentMaxWidth;
  final HocalistAccessibilityLayout accessibilityLayout;
  final bool accessibilityReflow;

  bool get usesAdaptiveLayout =>
      accessibilityLayout == HocalistAccessibilityLayout.adaptive;
  bool get usesStackedLayout =>
      accessibilityLayout == HocalistAccessibilityLayout.stacked;

  /// Normal-scale layouts preserve the approved composition. Accessibility
  /// layouts may wrap, grow, or reflow instead.
  bool get screenshotLocked => !accessibilityReflow;

  /// Only narrow phones use the legacy 390px replica canvas and FittedBox.
  /// Wider surfaces render directly at their fluid content width so tablets do
  /// not magnify a phone screenshot.
  bool get usesScaledReplicaCanvas =>
      !accessibilityReflow && availableWidth < referenceCanvasWidth;
  bool get isNarrow => widthClass == ApprovedReplicaWidthClass.narrow320;
  bool get isCompact => widthClass == ApprovedReplicaWidthClass.compact360;
  bool get isTablet => widthClass == ApprovedReplicaWidthClass.tablet;
  bool get isExpanded => availableWidth > referencePhoneMaxWidth;

  double get expansionProgress => _progress(
    availableWidth,
    referencePhoneMaxWidth,
    supportedViewportMaxWidth,
  );

  double geometry(double referencePixels) => referencePixels * geometryScale;

  double fontSize(double referencePixels) => referencePixels * typographyScale;

  /// Bounded spacing grows independently from geometry and typography.
  double spacing(double referencePixels, {double tabletMaxFactor = 1.35}) {
    if (availableWidth < referenceCanvasWidth) {
      return geometry(referencePixels);
    }
    return _lerp(
      referencePixels,
      referencePixels * tabletMaxFactor,
      expansionProgress,
    );
  }

  /// Artwork may grow modestly on tablets without scaling the entire page.
  double artSize(double referencePixels, {double tabletMaxFactor = 1.15}) {
    if (availableWidth < referenceCanvasWidth) {
      return geometry(referencePixels);
    }
    return _lerp(
      referencePixels,
      referencePixels * tabletMaxFactor,
      expansionProgress,
    );
  }

  double pageHorizontalPadding(double referencePixels) {
    return spacing(referencePixels, tabletMaxFactor: 1.5);
  }

  double lineHeight({
    required double referenceFontSize,
    required double referenceLineHeight,
  }) => referenceLineHeight / referenceFontSize;

  EdgeInsets geometryInsets(EdgeInsets referenceInsets) {
    return EdgeInsets.fromLTRB(
      geometry(referenceInsets.left),
      geometry(referenceInsets.top),
      geometry(referenceInsets.right),
      geometry(referenceInsets.bottom),
    );
  }

  Size geometrySize(Size referenceSize) {
    return Size(geometry(referenceSize.width), geometry(referenceSize.height));
  }

  double innerContentMaxWidth({required double referenceHorizontalInset}) {
    return math.max(
      0,
      contentMaxWidth - (pageHorizontalPadding(referenceHorizontalInset) * 2),
    );
  }

  static double _progress(double value, double start, double end) {
    if (end <= start) return 0;
    return ((value - start) / (end - start)).clamp(0.0, 1.0);
  }

  static double _lerp(double start, double end, double progress) {
    return start + ((end - start) * progress);
  }
}

class ApprovedReplicaScope extends InheritedWidget {
  const ApprovedReplicaScope({
    required this.metrics,
    required super.child,
    super.key,
  });

  final ApprovedReplicaMetrics metrics;

  static ApprovedReplicaMetrics of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ApprovedReplicaScope>();
    assert(scope != null, 'ApprovedReplicaScope is missing above this widget.');
    return scope!.metrics;
  }

  static ApprovedReplicaMetrics? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ApprovedReplicaScope>()
        ?.metrics;
  }

  @override
  bool updateShouldNotify(ApprovedReplicaScope oldWidget) {
    return metrics.availableWidth != oldWidget.metrics.availableWidth ||
        metrics.textScale != oldWidget.metrics.textScale ||
        metrics.widthClass != oldWidget.metrics.widthClass;
  }
}

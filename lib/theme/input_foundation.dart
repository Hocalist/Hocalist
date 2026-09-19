import 'package:flutter/material.dart';

/// Shared input geometry for Hocalist.
///
/// Screen-specific replicas may scale these values for narrow phones, but no
/// standard input should fall back to Material's cramped dense defaults.
abstract final class HocalistInputTokens {
  static const double minimumHeight = 48;
  static const double compactMinimumHeight = 44;
  static const double relatedFieldSpacing = 8;
  static const double horizontalPadding = 14;
  static const double verticalPadding = 12;
  static const double compactHorizontalPadding = 12;
  static const double compactVerticalPadding = 10;

  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: horizontalPadding,
    vertical: verticalPadding,
  );

  static const EdgeInsets compactContentPadding = EdgeInsets.symmetric(
    horizontal: compactHorizontalPadding,
    vertical: compactVerticalPadding,
  );
}

/// Shared geometry for interactive actions.
///
/// Full-width primary/secondary actions use a stable 48px minimum touch area,
/// while compact pill actions keep their visible shape without collapsing
/// their vertical breathing room. Screen replicas may scale these values, but
/// should not fall back to Material's implicit padding.
abstract final class HocalistButtonTokens {
  static const double minimumHeight = 48;
  static const double compactMinimumHeight = 32;
  static const double iconSize = 18;
  static const double horizontalPadding = 16;
  static const double verticalPadding = 13;
  static const double compactHorizontalPadding = 12;
  static const double compactVerticalPadding = 7;
  static const double radius = 14;

  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: horizontalPadding,
    vertical: verticalPadding,
  );

  static const EdgeInsets compactContentPadding = EdgeInsets.symmetric(
    horizontal: compactHorizontalPadding,
    vertical: compactVerticalPadding,
  );
}

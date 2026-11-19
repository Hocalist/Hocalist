import 'package:flutter/material.dart';

@immutable
class HocalistAccessibilityVisuals
    extends ThemeExtension<HocalistAccessibilityVisuals> {
  const HocalistAccessibilityVisuals({
    required this.buttonRadius,
    required this.buttonBackground,
    required this.buttonForeground,
    required this.buttonBorderWidth,
    this.fontFamily = 'Nunito',
  });

  final String fontFamily;
  final double buttonRadius;
  final Color buttonBackground;
  final Color buttonForeground;
  final double buttonBorderWidth;

  bool get usesHighContrastButton => buttonRadius <= 4;

  double radiusOr(double approvedRadius) =>
      usesHighContrastButton ? buttonRadius : approvedRadius;

  Color backgroundOr(Color approvedBackground) =>
      usesHighContrastButton ? buttonBackground : approvedBackground;

  Color foregroundOr(Color approvedForeground) =>
      usesHighContrastButton ? buttonForeground : approvedForeground;

  @override
  HocalistAccessibilityVisuals copyWith({
    String? fontFamily,
    double? buttonRadius,
    Color? buttonBackground,
    Color? buttonForeground,
    double? buttonBorderWidth,
  }) {
    return HocalistAccessibilityVisuals(
      fontFamily: fontFamily ?? this.fontFamily,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      buttonBackground: buttonBackground ?? this.buttonBackground,
      buttonForeground: buttonForeground ?? this.buttonForeground,
      buttonBorderWidth: buttonBorderWidth ?? this.buttonBorderWidth,
    );
  }

  @override
  HocalistAccessibilityVisuals lerp(
    covariant HocalistAccessibilityVisuals? other,
    double t,
  ) {
    if (other == null) return this;
    return HocalistAccessibilityVisuals(
      fontFamily: t < .5 ? fontFamily : other.fontFamily,
      buttonRadius: buttonRadius + (other.buttonRadius - buttonRadius) * t,
      buttonBackground: Color.lerp(
        buttonBackground,
        other.buttonBackground,
        t,
      )!,
      buttonForeground: Color.lerp(
        buttonForeground,
        other.buttonForeground,
        t,
      )!,
      buttonBorderWidth:
          buttonBorderWidth + (other.buttonBorderWidth - buttonBorderWidth) * t,
    );
  }
}

HocalistAccessibilityVisuals hocalistAccessibilityVisualsOf(
  BuildContext context,
) {
  return Theme.of(context).extension<HocalistAccessibilityVisuals>() ??
      const HocalistAccessibilityVisuals(
        buttonRadius: 16,
        buttonBackground: Color(0xff00036c),
        buttonForeground: Colors.white,
        buttonBorderWidth: 1,
      );
}

import 'package:flutter/material.dart';

/// Retains the approved light palette; resolves its semantic roles in dark mode.
abstract final class HocalistPalette {
  static Color? textOrNull(BuildContext context, Color? approved) =>
      approved == null ? null : text(context, approved);
  static Color? surfaceOrNull(BuildContext context, Color? approved) =>
      approved == null ? null : surface(context, approved);
  static Color text(BuildContext context, Color approved) =>
      textFor(Theme.of(context).brightness, approved);

  static Color textFor(Brightness brightness, Color approved) {
    if (brightness != Brightness.dark ||
        approved.a == 0 ||
        approved.computeLuminance() > .6) {
      return approved;
    }
    final hsl = HSLColor.fromColor(approved);
    if (hsl.saturation < .35) {
      return const Color(0xfff3f3ff).withValues(alpha: approved.a);
    }
    if (hsl.hue >= 190 && hsl.hue <= 285) {
      return const Color(0xffc4c5ff).withValues(alpha: approved.a);
    }
    return hsl.withLightness(.72).toColor();
  }

  static Color surface(BuildContext context, Color approved) {
    if (Theme.of(context).brightness != Brightness.dark || approved.a == 0) {
      return approved;
    }
    final luminance = approved.computeLuminance();
    if (luminance > .88) {
      return const Color(0xff15172d).withValues(alpha: approved.a);
    }
    if (luminance > .45) {
      return const Color(0xff202344).withValues(alpha: approved.a);
    }
    return approved;
  }

  static Color border(BuildContext context, Color approved) {
    if (Theme.of(context).brightness != Brightness.dark || approved.a == 0) {
      return approved;
    }
    final hsl = HSLColor.fromColor(approved);
    if (hsl.saturation > .5 && approved.computeLuminance() < .6) {
      return text(context, approved);
    }
    return const Color(0xff717590).withValues(alpha: approved.a);
  }
}

import 'package:flutter/material.dart';

import 'accessibility_visuals.dart';

/// The marketplace design is an explicit shared variant, not a replacement for
/// other approved Buyer/Seller surfaces. Values preserve the reviewed layout.
enum MarketplaceSurface { comparison, meetup }

class MarketplaceColors {
  MarketplaceColors.of(BuildContext context, {
    MarketplaceSurface surface = MarketplaceSurface.comparison,
  }) : dark = Theme.of(context).brightness == Brightness.dark,
       meetup = surface == MarketplaceSurface.meetup;

  final bool dark, meetup;
  Color get paper => dark ? Color(meetup ? 0xff201e33 : 0xff19192a) : Colors.white;
  Color get page => dark ? const Color(0xff111120) : const Color(0xfff7f7fc);
  Color get ink => dark ? const Color(0xfffaf8ff) : Color(meetup ? 0xff19152f : 0xff17152e);
  Color get muted => dark
      ? Color(meetup ? 0xffc2bada : 0xffb7b2ce)
      : Color(meetup ? 0xff625b76 : 0xff625e78);
  Color get border => dark ? const Color(0xff35314e) : const Color(0xffe9e6f4);
  Color get brand => dark
      ? Color(meetup ? 0xffc8bbff : 0xffc5b5ff)
      : Color(meetup ? 0xff3d24b7 : 0xff3920ba);
  Color get soft => dark ? const Color(0xff332652) : const Color(0xffeee9ff);
  Color get primary => dark
      ? Color(meetup ? 0xff5035ad : 0xff472d9c)
      : Color(meetup ? 0xff4027bc : 0xff3220b9);
}

abstract final class MarketplaceTypography {
  static TextStyle text(BuildContext context, double size, Color color, {
    FontWeight weight = FontWeight.w400, double? height = 1.4,
  }) {
    final selected = hocalistAccessibilityVisualsOf(context).fontFamily;
    // Default means the approved surface font. Explicit accessibility choices
    // still override it; system text scaling is applied by Flutter's Text.
    final family = selected == 'Lexend' || selected == 'Archivo' ? selected : 'Roboto';
    return TextStyle(fontFamily: family, fontSize: size, color: color,
        fontWeight: weight, height: height);
  }
}

/// Shared action for offer comparison and today's meetup. Normal appearance
/// matches the marketplace design, including icons on outlined actions.
class MarketplaceButton extends StatelessWidget {
  const MarketplaceButton({super.key, required this.label, required this.onPressed,
    required this.background, required this.foreground, this.border,
    this.icon, this.fontSize = 12, this.lineHeight = 1.4,
    this.padding = const EdgeInsets.all(5)});

  final String label;
  final VoidCallback? onPressed;
  final Color background, foreground;
  final BorderSide? border;
  final IconData? icon;
  final double fontSize, lineHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final accessibility = hocalistAccessibilityVisualsOf(context);
    final contrast = accessibility.usesHighContrastButton;
    final ink = accessibility.foregroundOr(foreground);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: accessibility.backgroundOr(background),
        minimumSize: const Size(0, 44),
        padding: padding,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: contrast ? BorderSide(color: ink, width: accessibility.buttonBorderWidth) : border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accessibility.radiusOr(10))),
        textStyle: MarketplaceTypography.text(context, fontSize, ink,
          weight: FontWeight.w600, height: lineHeight),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ]),
    );
  }
}

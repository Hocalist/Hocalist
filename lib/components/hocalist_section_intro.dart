import 'package:flutter/material.dart';
import '../theme/buyer_ui_foundation.dart';

/// Supplemental forms inherit the approved hierarchy rather than plain titles.
class HocalistSectionIntro extends StatelessWidget {
  const HocalistSectionIntro({
    required this.title,
    required this.icon,
    this.trailing,
    super.key,
  });
  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: BuyerUiTokens.softSurface,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: BuyerUiTokens.action, size: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.35,
              fontWeight: FontWeight.w800,
              color: BuyerUiTokens.text,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

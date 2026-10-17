import 'package:hocalist/theme/adaptive_palette.dart';
import 'package:flutter/material.dart';

import '../theme/buyer_ui_foundation.dart';
import '../theme/seller_ui_foundation.dart';
import 'hocalist_motion.dart';

/// Readable verification facts, never a score or an inferred account decision.
class HocalistStatusFact extends StatelessWidget {
  const HocalistStatusFact({
    required this.label,
    required this.confirmed,
    required this.icon,
    this.seller = false,
    super.key,
  });

  final String label;
  final bool confirmed;
  final IconData icon;
  final bool seller;

  @override
  Widget build(BuildContext context) {
    final accent = seller ? SellerUiColors.primaryBright : BuyerUiTokens.action;
    return AnimatedContainer(
      duration: HocalistMotion.duration(context),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(
          context,
          confirmed ? const Color(0xfff1f0ff) : Colors.white,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: HocalistPalette.border(
            context,
            confirmed ? const Color(0xffd9d5ff) : BuyerUiTokens.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: HocalistPalette.text(context, accent),
              ),
              const Spacer(),
              Icon(
                confirmed
                    ? Icons.check_circle_outline_rounded
                    : Icons.radio_button_unchecked,
                size: 17,
                color: HocalistPalette.text(
                  context,
                  confirmed ? accent : BuyerUiTokens.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: HocalistPalette.text(context, BuyerUiTokens.text),
            ),
          ),
        ],
      ),
    );
  }
}

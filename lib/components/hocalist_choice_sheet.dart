import 'package:flutter/material.dart';

import '../theme/adaptive_palette.dart';
import '../theme/buyer_ui_foundation.dart';
import '../theme/seller_ui_foundation.dart';

/// A single selection in a sheet. The enclosing role sheet supplies typography.
class HocalistSheetChoice extends StatelessWidget {
  const HocalistSheetChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.seller = false,
    super.key,
  });

  final String label;
  final bool selected, seller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = HocalistPalette.text(
      context,
      seller ? SellerUiColors.primaryBright : BuyerUiTokens.action,
    );
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: HocalistPalette.surface(
            context,
            selected
                ? (seller
                      ? SellerUiColors.lavender
                      : BuyerUiTokens.activeSurface)
                : Colors.white,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: HocalistPalette.border(
                context,
                selected
                    ? accent
                    : (seller ? SellerUiColors.line : BuyerUiTokens.border),
              ),
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      color: accent,
                      size: 19,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

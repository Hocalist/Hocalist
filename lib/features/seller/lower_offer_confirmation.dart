import 'package:flutter/material.dart';
import '../../theme/seller_ui_foundation.dart';

Future<bool?> confirmLowerOffer(
  BuildContext context,
  int priceMinor,
  int minimumMinor,
) async => await showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheet) => SellerModalSheet(
    icon: Icons.sell_outlined,
    title: 'Send a lower offer?',
    subtitle:
        'Your offer of \$${(priceMinor / 100).toStringAsFixed(2)} is below the buyer’s minimum budget of \$${(minimumMinor / 100).toStringAsFixed(2)}.',
    onClose: () => Navigator.pop(sheet),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SellerPrimaryButton(
          label: 'Send offer',
          onPressed: () => Navigator.pop(sheet, true),
        ),
        const SizedBox(height: 8),
        SellerSecondaryButton(
          label: 'Edit price',
          onPressed: () => Navigator.pop(sheet, false),
        ),
      ],
    ),
  ),
);

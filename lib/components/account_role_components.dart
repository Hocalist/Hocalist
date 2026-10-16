import 'package:flutter/material.dart';
import '../theme/buyer_ui_foundation.dart';
import '../theme/seller_ui_foundation.dart';

class AccountActionButton extends StatelessWidget {
  const AccountActionButton({
    required this.seller,
    required this.label,
    required this.onPressed,
    super.key,
  });
  final bool seller;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => seller
      ? SellerPrimaryButton(label: label, onPressed: onPressed)
      : BuyerPrimaryButton(label: label, onPressed: onPressed);
}

class AccountStateNotice extends StatelessWidget {
  const AccountStateNotice({
    required this.seller,
    required this.icon,
    required this.title,
    this.tone = BuyerNoticeTone.neutral,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final bool seller;
  final IconData icon;
  final String title;
  final BuyerNoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => seller
      ? SellerStateNotice(
          icon: icon,
          title: title,
          tone: SellerNoticeTone.values.byName(tone.name),
          actionLabel: actionLabel,
          onAction: onAction,
        )
      : BuyerStateNotice(
          icon: icon,
          title: title,
          tone: tone,
          actionLabel: actionLabel,
          onAction: onAction,
        );
}

import 'package:flutter/material.dart';
import '../theme/buyer_ui_foundation.dart';
import '../theme/seller_ui_foundation.dart';

class AccountModalSheet extends StatelessWidget {
  const AccountModalSheet({
    required this.seller,
    required this.title,
    required this.icon,
    required this.onClose,
    required this.child,
    this.subtitle,
    super.key,
  });

  final bool seller;
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => seller
      ? SellerModalSheet(
          title: title,
          icon: icon,
          subtitle: subtitle ?? '',
          onClose: onClose,
          child: child,
        )
      : BuyerModalSheet(
          title: title,
          icon: icon,
          subtitle: subtitle,
          onClose: onClose,
          child: child,
        );
}

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

class AccountSecondaryButton extends StatelessWidget {
  const AccountSecondaryButton({
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
      ? SellerSecondaryButton(label: label, onPressed: onPressed)
      : BuyerSecondaryButton(label: label, onPressed: onPressed);
}

class AccountStateNotice extends StatelessWidget {
  const AccountStateNotice({
    required this.seller,
    required this.icon,
    required this.title,
    this.tone = BuyerNoticeTone.neutral,
    this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final bool seller;
  final IconData icon;
  final String title;
  final BuyerNoticeTone tone;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => seller
      ? SellerStateNotice(
          icon: icon,
          title: title,
          body: body,
          tone: SellerNoticeTone.values.byName(tone.name),
          actionLabel: actionLabel,
          onAction: onAction,
        )
      : BuyerStateNotice(
          icon: icon,
          title: title,
          body: body,
          tone: tone,
          actionLabel: actionLabel,
          onAction: onAction,
        );
}

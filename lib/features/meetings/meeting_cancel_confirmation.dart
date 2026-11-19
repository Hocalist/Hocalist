import 'package:flutter/material.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../components/hocalist_choice_sheet.dart';

Future<bool> confirmMeetingCancellation(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => BuyerModalSheet(
        title: 'Cancel this meeting?',
        icon: Icons.event_busy_outlined,
        onClose: () => Navigator.pop(sheet, false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This will cancel the agreed meeting time and location for both of you. It will not confirm a purchase.',
            ),
            const SizedBox(height: 16),
            BuyerPrimaryButton(
              label: 'Keep meeting',
              onPressed: () => Navigator.pop(sheet, false),
            ),
            const SizedBox(height: 8),
            BuyerSecondaryButton(
              label: 'Cancel meeting',
              onPressed: () => Navigator.pop(sheet, true),
            ),
          ],
        ),
      ),
    ) ==
    true;

Future<String?> chooseCancellationReason(BuildContext context) {
  String? selected;
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => StatefulBuilder(
      builder: (context, setSheetState) => SellerModalSheet(
        title: 'Why are you canceling?',
        icon: Icons.event_busy_outlined,
        subtitle:
            'Select a reason to cancel this meeting. Admin can review your reason.',
        onClose: () => Navigator.pop(sheet),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final reason in const [
              "I can't make the destination",
              "I can't make the time requested",
              'Buyer keeps changing proposal',
              'Unforeseen circumstances',
            ])
              HocalistSheetChoice(
                label: reason,
                seller: true,
                selected: selected == reason,
                onTap: () => setSheetState(() => selected = reason),
              ),
            SellerPrimaryButton(
              label: 'Cancel meeting',
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(sheet, selected),
            ),
            const SizedBox(height: 8),
            SellerSecondaryButton(
              label: 'Keep meeting',
              onPressed: () => Navigator.pop(sheet),
            ),
          ],
        ),
      ),
    ),
  );
}

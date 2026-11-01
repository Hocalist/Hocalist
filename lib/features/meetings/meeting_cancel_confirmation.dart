import 'package:flutter/material.dart';
import '../../theme/buyer_ui_foundation.dart';

Future<bool> confirmMeetingCancellation(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context, useSafeArea: true, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => BuyerModalSheet(
        title: 'Cancel this meeting?', icon: Icons.event_busy_outlined,
        onClose: () => Navigator.pop(sheet, false),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This will cancel the agreed meeting time and location for both of you. It will not confirm a purchase.'),
          const SizedBox(height: 16),
          BuyerPrimaryButton(label: 'Keep meeting', onPressed: () => Navigator.pop(sheet, false)),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Cancel meeting')),
        ]),
      ),
    ) == true;

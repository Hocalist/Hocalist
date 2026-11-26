import 'package:flutter/material.dart';

import '../../components/hocalist_choice_sheet.dart';
import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/meetings/meeting_adapter.dart';
import '../../theme/buyer_ui_foundation.dart';

Future<BuyerMeetupAction?> showBuyerMeetupOptions(
  BuildContext context, {
  required bool canReschedule,
}) => showModalBottomSheet<BuyerMeetupAction>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheet) => BuyerModalSheet(
    title: 'Manage meetup',
    icon: Icons.tune,
    onClose: () => Navigator.pop(sheet),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BuyerPrimaryButton(
        label: 'Reschedule meetup',
        onPressed: canReschedule
            ? () => Navigator.pop(sheet, BuyerMeetupAction.reschedule)
            : null,
      ),
      if (!canReschedule)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('There is already a change awaiting confirmation.'),
        ),
      const SizedBox(height: 8),
      BuyerSecondaryButton(
        label: 'Cancel meetup',
        onPressed: () => Navigator.pop(sheet, BuyerMeetupAction.cancel),
      ),
    ]),
  ),
);

Future<BuyerMeetupChange?> chooseBuyerMeetupReason(
  BuildContext context,
  BuyerMeetupAction action,
) async {
  final reschedule = action == BuyerMeetupAction.reschedule;
  final reasons = {
    if (reschedule) 'running_late': 'Running late',
    'schedule_changed': 'Schedule changed',
    if (reschedule) 'transportation': 'Transportation issue',
    if (!reschedule) 'cant_get_there': 'Can’t get there',
    if (!reschedule) 'no_longer_needed': 'No longer need it',
    'other': 'Other',
  };
  String? selected;
  var note = '';
  return showModalBottomSheet<BuyerMeetupChange>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => BuyerModalSheet(
      title: reschedule ? 'Why reschedule?' : 'Why cancel?',
      subtitle: 'The seller can see the reason you choose.',
      icon: Icons.event_note_outlined,
      onClose: () => Navigator.pop(sheet),
      child: StatefulBuilder(
        builder: (context, changeSelection) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final reason in reasons.entries)
              HocalistSheetChoice(
                label: reason.value,
                selected: selected == reason.key,
                onTap: () => changeSelection(() => selected = reason.key),
              ),
            if (selected == 'other')
              TextField(
                decoration: const InputDecoration(labelText: 'Note for the seller (optional)'),
                maxLength: 180,
                maxLines: 2,
                onChanged: (value) => note = value,
              ),
            BuyerPrimaryButton(
              label: 'Continue',
              onPressed: selected == null ? null : () => Navigator.pop(
                sheet,
                BuyerMeetupChange(
                  action: action,
                  reason: selected!,
                  note: selected == 'other' && note.trim().isNotEmpty ? note.trim() : null,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool?> confirmBuyerMeetupCancellation(
  BuildContext context, {
  required String summary,
  required Future<MeetingActionResult> Function(String key) cancel,
}) {
  var busy = false;
  var uncertain = false;
  String? error;
  final key = LocalMarketplaceRepository.newStoreOperationKey('buyer-meetup-cancel');
  return showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheet) => StatefulBuilder(
      builder: (context, update) => PopScope(
        canPop: !busy && !uncertain,
        child: BuyerModalSheet(
          title: 'Cancel this meetup?',
          subtitle: summary,
          icon: Icons.event_busy_outlined,
          onClose: () {
            if (!busy && !uncertain) Navigator.pop(sheet);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('This cancels the meetup for both of you. Your buying request stays open.'),
            if (error != null)
              Padding(padding: const EdgeInsets.only(top: 8),
                child: Semantics(liveRegion: true, child: Text(error!))),
            const SizedBox(height: 12),
            BuyerPrimaryButton(
              label: 'Keep meetup',
              onPressed: busy || uncertain ? null : () => Navigator.pop(sheet, false),
            ),
            const SizedBox(height: 8),
            BuyerSecondaryButton(
              label: busy ? 'Canceling…' : uncertain ? 'Retry cancellation' : 'Confirm cancellation',
              onPressed: busy ? null : () async {
                if (busy) return;
                update(() { busy = true; error = null; });
                MeetingActionResult result;
                try {
                  result = await cancel(key);
                } catch (_) {
                  result = const MeetingActionResult.failure(
                    'Could not confirm cancellation. Retry to check it safely.',
                    outcomeUncertain: true,
                  );
                }
                if (!sheet.mounted) return;
                if (result.isSuccess) {
                  Navigator.pop(sheet, true);
                  return;
                }
                update(() {
                  busy = false;
                  uncertain = result.outcomeUncertain;
                  error = result.error;
                });
              },
            ),
          ]),
        ),
      ),
    ),
  );
}

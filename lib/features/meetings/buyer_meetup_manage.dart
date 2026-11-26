import 'package:flutter/material.dart';

import '../../components/hocalist_choice_sheet.dart';
import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/meetings/meeting_adapter.dart';
import '../../theme/buyer_ui_foundation.dart';

class BuyerMeetupManagePanel extends StatefulWidget {
  const BuyerMeetupManagePanel({
    required this.canReschedule,
    required this.onClose,
    required this.onContinue,
    super.key,
  });

  final bool canReschedule;
  final VoidCallback onClose;
  final ValueChanged<BuyerMeetupChange> onContinue;

  @override
  State<BuyerMeetupManagePanel> createState() => _BuyerMeetupManagePanelState();
}

class _BuyerMeetupManagePanelState extends State<BuyerMeetupManagePanel> {
  BuyerMeetupAction? _action;
  String? _selected;
  String _note = '';

  @override
  Widget build(BuildContext context) {
    final action = _action;
    final reschedule = action == BuyerMeetupAction.reschedule;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xfffaf8ff) : const Color(0xff19152f);
    final muted = dark ? const Color(0xffc2bada) : const Color(0xff625b76);
    final border = dark ? const Color(0xff38324f) : const Color(0xffe7e1f4);
    final fill = dark ? const Color(0xff161525) : const Color(0xfff7f7fc);
    final danger = dark ? const Color(0xffff9db4) : const Color(0xffa32442);
    final primary = dark ? const Color(0xff5035ad) : const Color(0xff4027bc);
    final reasons = {
      if (reschedule) 'running_late': 'Running late',
      'schedule_changed': 'Schedule changed',
      if (reschedule) 'transportation': 'Transportation issue',
      if (!reschedule) 'cant_get_there': 'Can’t get there',
      if (!reschedule) 'no_longer_needed': 'No longer need it',
      'other': 'Other',
    };
    Widget option(String label, VoidCallback? onPressed, {bool isPrimary = false, bool isDanger = false}) =>
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: isPrimary ? Colors.white : isDanger ? danger : ink,
            backgroundColor: isPrimary ? primary : fill,
            side: BorderSide(color: isPrimary ? Colors.transparent : border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(label),
        );
    return Container(
      key: const Key('buyer-meetup-manage-panel'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff201e33) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Semantics(header: true, liveRegion: true, child: Text(
            action == null ? 'Manage meetup' : reschedule ? 'Why reschedule?' : 'Why cancel?',
            style: TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w700, color: ink),
          ))),
          IconButton(tooltip: 'Close manage menu', onPressed: widget.onClose,
            icon: Icon(Icons.close, size: 17, color: muted)),
        ]),
        if (action == null) ...[
          option('Reschedule meetup', widget.canReschedule
              ? () => setState(() => _action = BuyerMeetupAction.reschedule) : null),
          if (!widget.canReschedule)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(
              'There is already a change awaiting confirmation.', style: TextStyle(fontSize: 12, color: muted),
            )),
          const SizedBox(height: 7),
          option('Cancel meetup', () => setState(() => _action = BuyerMeetupAction.cancel), isDanger: true),
        ] else ...[
          for (final reason in reasons.entries)
            HocalistSheetChoice(label: reason.value, selected: _selected == reason.key,
              onTap: () => setState(() => _selected = reason.key)),
          if (_selected == 'other')
            TextField(
              decoration: const InputDecoration(labelText: 'Note for the seller (optional)'),
              maxLength: 180, maxLines: 2,
              onChanged: (value) => _note = value,
            ),
          option('Continue', _selected == null ? null : () => widget.onContinue(BuyerMeetupChange(
            action: action,
            reason: _selected!,
            note: _selected == 'other' && _note.trim().isNotEmpty ? _note.trim() : null,
          )), isPrimary: true),
        ],
      ]),
    );
  }
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

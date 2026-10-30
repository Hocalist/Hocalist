import 'package:hocalist/components/hocalist_loading_indicator.dart';
import 'package:flutter/material.dart';
import '../../data/phase2/meetings/meeting_codecs.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../../theme/seller_ui_foundation.dart';

/// Participant-specific next steps, kept beside the deal inside its chat.
/// Every action receives the displayed meeting, never a global selected deal.
class ConversationMeetingActions extends StatefulWidget {
  const ConversationMeetingActions({
    super.key,
    required this.meetings,
    this.selectedDealId,
    this.compact = false,
    required this.viewerUserId,
    required this.completedIds,
    required this.onAccept,
    this.onDecline,
    required this.onReschedule,
    required this.onDirections,
    required this.onChoosePurchase,
    required this.onReview,
    required this.confirmationBuilder,
  });
  final List<MeetingView> meetings;
  final String? selectedDealId;
  final bool compact;
  final String viewerUserId;
  final Set<String> completedIds;
  final Future<void> Function(MeetingView) onAccept,
      onReschedule,
      onDirections,
      onChoosePurchase,
      onReview;
  final Widget Function(MeetingView) confirmationBuilder;
  final Future<void> Function(MeetingView)? onDecline;
  @override
  State<ConversationMeetingActions> createState() =>
      _ConversationMeetingActionsState();
}

class _ConversationMeetingActionsState
    extends State<ConversationMeetingActions> {
  bool busy = false;
  String? error;
  @override
  void didUpdateWidget(ConversationMeetingActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDealId != widget.selectedDealId) error = null;
  }

  MeetingView? get selected {
    if (widget.selectedDealId != null) {
      return widget.meetings
          .where(
            (m) =>
                m.meetingId == widget.selectedDealId ||
                m.offerId == widget.selectedDealId,
          )
          .firstOrNull;
    }
    return widget.meetings
            .where(
              (m) =>
                  !widget.completedIds.contains(m.meetingId) && !m.isCancelled,
            )
            .firstOrNull ??
        widget.meetings.firstOrNull;
  }

  Future<void> run(
    MeetingView meeting,
    Future<void> Function(MeetingView) action,
  ) async {
    if (busy) return;
    final id = meeting.meetingId;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action(meeting);
    } catch (_) {
      if (mounted && selected?.meetingId == id) {
        setState(
          () => error =
              'Could not confirm the change. Try again to check its status.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meeting = selected;
    if (meeting == null ||
        (meeting.buyerUserId != widget.viewerUserId &&
            meeting.sellerUserId != widget.viewerUserId)) {
      return const SizedBox.shrink();
    }
    final buyer = meeting.buyerUserId == widget.viewerUserId;
    final done = widget.completedIds.contains(meeting.meetingId);
    final pending = meeting.pendingSchedule;
    final accepted = meeting.acceptedSchedule;
    final sellerConfirmed = meeting.purchaseSelected;
    final mustRespond =
        sellerConfirmed &&
        pending != null &&
        pending.proposedByUserId != widget.viewerUserId;
    final schedule = accepted ?? pending;
    String describe(MeetingScheduleView value) {
      final locale = MaterialLocalizations.of(context);
      final date = locale.formatMediumDate(
        DateTime(value.date.year, value.date.month, value.date.day),
      );
      final time = locale.formatTimeOfDay(
        TimeOfDay(hour: value.startTime.hour, minute: value.startTime.minute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      final zone = value.timezoneId.split('/').last.replaceAll('_', ' ');
      return '$date · $time\n$zone time · ${value.placeLabel ?? value.placeAddress ?? "Confirm the location"}';
    }

    final title = done
        ? 'Purchase completed'
        : !sellerConfirmed
        ? (buyer
              ? 'Confirm your seller first'
              : 'Waiting for buyer confirmation')
        : meeting.isCancelled
        ? 'Meeting cancelled'
        : pending != null
        ? (mustRespond
              ? 'Meeting needs your acceptance'
              : 'Waiting for acceptance')
        : accepted != null
        ? 'Your meeting is set'
        : 'Arrange your meeting';
    Widget button(String label, Future<void> Function(MeetingView) action) =>
        buyer
        ? BuyerPrimaryButton(
            label: label,
            compact: widget.compact,
            onPressed: busy ? null : () => run(meeting, action),
          )
        : SellerPrimaryButton(
            label: label,
            compact: widget.compact,
            onPressed: busy ? null : () => run(meeting, action),
          );
    Widget notice({
      required IconData icon,
      required String title,
      String? body,
      BuyerNoticeTone tone = BuyerNoticeTone.brand,
    }) => buyer
        ? BuyerStateNotice(icon: icon, title: title, body: body, tone: tone)
        : SellerStateNotice(
            icon: icon,
            title: title,
            body: body,
            tone: SellerNoticeTone.values.byName(tone.name),
          );
    if (widget.compact) {
      final summary = schedule == null
          ? null
          : describe(schedule).split('\n').first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (summary != null && !done) Text(summary),
          if (pending != null && accepted != null && !done)
            Text(
              'Proposed: ${describe(pending).split('\n').first} · awaiting acceptance',
            ),
          if (error != null) Text(error!, semanticsLabel: error),
          if (busy) const HocalistLoadingIndicator(),
          if (!done && !meeting.isCancelled) ...[
            if (buyer && !sellerConfirmed)
              button('Confirm this seller', widget.onChoosePurchase),
            if (mustRespond) button('Accept meeting', widget.onAccept),
            Wrap(
              children: [
                if (mustRespond && widget.onDecline != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(meeting, widget.onDecline!),
                    child: const Text('Decline proposed time'),
                  ),
                if (sellerConfirmed && pending == null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(meeting, widget.onReschedule),
                    child: Text(
                      accepted == null
                          ? 'Propose a date or time'
                          : 'Change meeting',
                    ),
                  ),
                if (sellerConfirmed && accepted != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(meeting, widget.onDirections),
                    child: const Text('Directions'),
                  ),
              ],
            ),
            if (sellerConfirmed && accepted != null && pending == null)
              ExpansionTile(
                key: ValueKey('purchase-controls-${meeting.meetingId}'),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  buyer ? 'Your purchase PIN' : 'Confirm completed purchase',
                ),
                children: [widget.confirmationBuilder(meeting)],
              ),
          ],
          if (done && buyer) button('Review your purchase', widget.onReview),
          if (done && !buyer) const Text('This sale is complete.'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        notice(
          icon: done ? Icons.check_circle_outline : Icons.event_outlined,
          title: title,
          tone: done ? BuyerNoticeTone.success : BuyerNoticeTone.brand,
          body: done
              ? 'Item payment stays between buyer and seller.'
              : !sellerConfirmed
              ? 'The buyer confirms the seller before either person proposes a meeting.'
              : schedule == null
              ? null
              : describe(schedule),
        ),
        if (pending != null &&
            accepted != null &&
            !done &&
            sellerConfirmed &&
            !meeting.isCancelled)
          notice(
            icon: Icons.update,
            title: 'Proposed new time',
            body:
                '${describe(pending)}\nThe agreed time stays in place until both accept.',
          ),
        if (error != null)
          notice(
            icon: Icons.error_outline,
            title: error!,
            tone: BuyerNoticeTone.error,
          ),
        if (busy) const HocalistLoadingIndicator(),
        if (!done && !meeting.isCancelled) ...[
          if (buyer && !sellerConfirmed)
            button('Confirm this seller', widget.onChoosePurchase),
          if (mustRespond) button('Accept meeting', widget.onAccept),
          if (mustRespond && widget.onDecline != null)
            TextButton(
              onPressed: busy ? null : () => run(meeting, widget.onDecline!),
              child: const Text('Decline proposed time'),
            ),
          if (sellerConfirmed && pending == null)
            TextButton(
              onPressed: busy ? null : () => run(meeting, widget.onReschedule),
              child: Text(
                accepted == null
                    ? 'Propose a date or time'
                    : 'Propose a new date or time',
              ),
            ),
          if (sellerConfirmed && accepted != null)
            TextButton.icon(
              onPressed: busy ? null : () => run(meeting, widget.onDirections),
              icon: const Icon(Icons.directions_outlined),
              label: const Text('View directions'),
            ),
          if (sellerConfirmed && accepted != null && pending == null)
            widget.confirmationBuilder(meeting),
        ],
        if (done && buyer) button('Review your purchase', widget.onReview),
        if (done && !buyer)
          const Text(
            'This sale is complete. No further PIN or meeting action is needed.',
          ),
      ],
    );
  }
}

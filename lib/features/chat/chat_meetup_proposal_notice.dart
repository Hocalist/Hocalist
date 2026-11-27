import 'package:flutter/material.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/meetings/meeting_codecs.dart';
import '../../theme/buyer_ui_foundation.dart';

typedef ChatMeetupProposal = ({MeetingView meeting, String title});
typedef ChatMeetupResponse =
    Future<MeetingActionResult?> Function(MeetingView meeting, bool accept);
typedef ChatPriceProposal = ({
  String offerId,
  String revisionId,
  String title,
  String currentPrice,
  String proposedPrice,
  bool incoming,
});
typedef ChatPriceResponse =
    Future<String?> Function(ChatPriceProposal proposal, bool accept);
typedef _Review = ({
  Object id,
  String label,
  String title,
  WidgetBuilder details,
  Future<({bool saved, String? error})> Function(bool) respond,
});

class ChatMeetupProposalNotice extends StatefulWidget {
  const ChatMeetupProposalNotice({
    super.key,
    required this.proposals,
    required this.respond,
    required this.viewerIsSeller,
    this.priceProposals = const [],
    this.respondToPrice,
  });

  final List<ChatMeetupProposal> proposals;
  final ChatMeetupResponse respond;
  final bool viewerIsSeller;
  final List<ChatPriceProposal> priceProposals;
  final ChatPriceResponse? respondToPrice;

  @override
  State<ChatMeetupProposalNotice> createState() =>
      _ChatMeetupProposalNoticeState();
}

class _ChatMeetupProposalNoticeState extends State<ChatMeetupProposalNotice> {
  final _shown = <Object>{};
  bool _dialogOpen = false;

  String get _counterpart => widget.viewerIsSeller ? 'buyer' : 'seller';

  Iterable<_Review> get _reviews sync* {
    for (final proposal in widget.proposals) {
      final meeting = proposal.meeting;
      yield (
        id: (meeting.meetingId, meeting.pendingSchedule!.sequence),
        label: 'Review meetup proposal · ${proposal.title}',
        title: meeting.hasAcceptedSchedule
            ? 'Meetup change proposed'
            : 'Meetup proposed',
        details: (_) =>
            _MeetupComparison(proposal: proposal, counterpart: _counterpart),
        respond: (accept) async {
          final result = await widget.respond(meeting, accept);
          return (saved: result?.isSuccess == true, error: result?.error);
        },
      );
    }
    final respondToPrice = widget.respondToPrice;
    if (respondToPrice == null) return;
    for (final price in widget.priceProposals.where((row) => row.incoming)) {
      yield (
        id: price.revisionId,
        label: 'Review price proposal · ${price.title}',
        title: 'Price change proposed',
        details: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The $_counterpart proposed a price change for ${price.title}.',
            ),
            const SizedBox(height: 12),
            Text('Current price: ${price.currentPrice}'),
            Text('Proposed price: ${price.proposedPrice}'),
            const SizedBox(height: 12),
            const Text('The current price stays in place unless you accept.'),
          ],
        ),
        respond: (accept) async {
          final error = await respondToPrice(price, accept);
          return (saved: error == null, error: error);
        },
      );
    }
  }

  Future<void> _review(_Review proposal) async {
    if (!mounted ||
        _dialogOpen ||
        ModalRoute.of(context)?.isCurrent == false ||
        !_reviews.any((current) => current.id == proposal.id)) {
      return;
    }
    _dialogOpen = true;
    _shown.add(proposal.id);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ProposalDialog(proposal: proposal),
      );
    } finally {
      _dialogOpen = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final proposals = _reviews.toList();
    final unseen = proposals.where((p) => !_shown.contains(p.id)).firstOrNull;
    if (current && !_dialogOpen && unseen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_shown.contains(unseen.id)) _review(unseen);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final proposal in proposals)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: BuyerSecondaryButton(
              label: proposal.label,
              onPressed: () => _review(proposal),
              compact: true,
            ),
          ),
      ],
    );
  }
}

class _ProposalDialog extends StatefulWidget {
  const _ProposalDialog({required this.proposal});

  final _Review proposal;

  @override
  State<_ProposalDialog> createState() => _ProposalDialogState();
}

class _ProposalDialogState extends State<_ProposalDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _submit(bool accept) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final result = await widget.proposal.respond(accept);
      if (!mounted) return;
      if (result.saved) {
        Navigator.of(context).pop();
        return;
      }
      error = result.error;
    } catch (_) {
      error = 'Could not save your response. Try again.';
    }
    if (mounted)
      setState(() {
        _busy = false;
        _error = error;
      });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.proposal.title),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.proposal.details(context),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _submit(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _submit(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }
}

class _MeetupComparison extends StatelessWidget {
  const _MeetupComparison({required this.proposal, required this.counterpart});

  final ChatMeetupProposal proposal;
  final String counterpart;

  String _details(BuildContext context, MeetingScheduleView schedule) {
    final locale = MaterialLocalizations.of(context);
    final date = locale.formatFullDate(
      DateTime(schedule.date.year, schedule.date.month, schedule.date.day),
    );
    final time = locale.formatTimeOfDay(
      TimeOfDay(
        hour: schedule.startTime.hour,
        minute: schedule.startTime.minute,
      ),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final zone = schedule.timezoneId.replaceAll('_', ' ');
    final address = schedule.placeAddress?.trim();
    final label = schedule.placeLabel?.trim();
    final place = <String>{
      if (label?.isNotEmpty == true) label!,
      if (address?.isNotEmpty == true) address!,
    }.join('\n');
    final destination = place.isEmpty ? 'Location to be arranged' : place;
    return '$date · $time ($zone)\n$destination';
  }

  @override
  Widget build(BuildContext context) {
    final meeting = proposal.meeting;
    final agreed = meeting.acceptedSchedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          agreed == null
              ? 'The $counterpart proposed a meetup for ${proposal.title}.'
              : 'The $counterpart proposed a meetup change for ${proposal.title}.',
        ),
        if (agreed != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Current meetup',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(_details(context, agreed)),
        ],
        const SizedBox(height: 12),
        const Text(
          'Proposed meetup',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(_details(context, meeting.pendingSchedule!)),
        const SizedBox(height: 12),
        Text(
          agreed == null
              ? 'Accept to confirm this meetup.'
              : 'Your current meetup stays confirmed unless you accept this change.',
        ),
      ],
    );
  }
}

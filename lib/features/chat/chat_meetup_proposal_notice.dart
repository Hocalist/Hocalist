import 'package:flutter/material.dart';

import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/meetings/meeting_codecs.dart';
import '../../theme/buyer_ui_foundation.dart';

typedef ChatMeetupProposal = ({MeetingView meeting, String title});
typedef ChatMeetupResponse =
    Future<MeetingActionResult?> Function(MeetingView meeting, bool accept);

class ChatMeetupProposalNotice extends StatefulWidget {
  const ChatMeetupProposalNotice({
    super.key,
    required this.proposals,
    required this.respond,
    required this.viewerIsSeller,
  });

  final List<ChatMeetupProposal> proposals;
  final ChatMeetupResponse respond;
  final bool viewerIsSeller;

  @override
  State<ChatMeetupProposalNotice> createState() =>
      _ChatMeetupProposalNoticeState();
}

class _ChatMeetupProposalNoticeState extends State<ChatMeetupProposalNotice> {
  final _shown = <(String, int)>{};
  bool _dialogOpen = false;

  (String, int) _identity(ChatMeetupProposal proposal) =>
      (proposal.meeting.meetingId, proposal.meeting.pendingSchedule!.sequence);

  Future<void> _review(ChatMeetupProposal proposal) async {
    if (!mounted ||
        _dialogOpen ||
        ModalRoute.of(context)?.isCurrent == false ||
        !widget.proposals.any(
          (current) => _identity(current) == _identity(proposal),
        )) {
      return;
    }
    _dialogOpen = true;
    _shown.add(_identity(proposal));
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ProposalDialog(
          proposal: proposal,
          respond: widget.respond,
          counterpart: widget.viewerIsSeller ? 'buyer' : 'seller',
        ),
      );
    } finally {
      _dialogOpen = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final unseen = widget.proposals
        .where((p) => !_shown.contains(_identity(p)))
        .lastOrNull;
    if (current && !_dialogOpen && unseen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_shown.contains(_identity(unseen))) _review(unseen);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final proposal in widget.proposals)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: BuyerSecondaryButton(
              label: 'Review meetup proposal · ${proposal.title}',
              onPressed: () => _review(proposal),
              compact: true,
            ),
          ),
      ],
    );
  }
}

class _ProposalDialog extends StatefulWidget {
  const _ProposalDialog({
    required this.proposal,
    required this.counterpart,
    required this.respond,
  });

  final ChatMeetupProposal proposal;
  final String counterpart;
  final ChatMeetupResponse respond;

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
      final result = await widget.respond(widget.proposal.meeting, accept);
      if (!mounted) return;
      if (result?.isSuccess == true) {
        Navigator.of(context).pop();
        return;
      }
      if (result != null)
        error = result.error ?? 'Could not save your response.';
    } catch (_) {
      error = 'Could not save your response. Try again.';
    }
    if (mounted)
      setState(() {
        _busy = false;
        _error = error;
      });
  }

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
    final meeting = widget.proposal.meeting;
    final agreed = meeting.acceptedSchedule;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          agreed == null ? 'Meetup proposed' : 'Meetup change proposed',
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              agreed == null
                  ? 'The ${widget.counterpart} proposed a meetup for ${widget.proposal.title}.'
                  : 'The ${widget.counterpart} proposed a meetup change for ${widget.proposal.title}.',
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

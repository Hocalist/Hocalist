import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../data/phase2/media/image_gateway.dart';
import '../media/private_image_picker.dart';
import '../../theme/control_foundation.dart';
import '../../components/pull_refresh.dart';
import '../../components/hocalist_section_intro.dart';
import '../../components/hocalist_choice_sheet.dart';
import '../../components/account_role_components.dart';
import '../../components/hocalist_account_field.dart';
import '../../data/local_marketplace_repository.dart';
import '../../data/phase2/support/support_adapter.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';

class SupportCasesPage extends StatefulWidget {
  const SupportCasesPage({
    required this.adapter,
    required this.onBack,
    this.conversationId,
    this.sellerOfferId,
    this.initialReasonCode,
    this.generalHelp = false,
    this.seller = false,
    super.key,
  });
  final SupportAdapter adapter;
  final String? initialReasonCode;
  final bool generalHelp, seller;
  final VoidCallback onBack;

  /// A user-visible reference, not a grant to read the conversation or its messages.
  final String? conversationId;
  final String? sellerOfferId;
  @override
  State<SupportCasesPage> createState() => _SupportCasesPageState();
}

class _SupportCasesPageState extends State<SupportCasesPage> {
  final _body = TextEditingController();
  List<SupportReason> _reasons = [];
  List<SupportCase> _cases = [];
  String? _reason, _cursor, _error, _ack;
  String? _formError;
  bool _retryDiscarded = false;
  bool _loading = true, _sending = false;
  bool _feedback = false, _includeDevice = true, _uploadPending = false;
  String _feedbackType = 'Problem';
  List<String> _screenshots = [];
  int _pickerVersion = 0;
  int _generation = 0;
  ({String reason, String body, String key, String? sellerOfferId})? _intent;
  String get _reference => widget.conversationId == null || widget.sellerOfferId != null
      ? ''
      : '\n\nConversation reference: ${widget.conversationId}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _body.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final g = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final reasons = await widget.adapter.reasons();
    if (!mounted || g != _generation) return;
    final cases = await widget.adapter.cases(cursor: more ? _cursor : null);
    if (!mounted || g != _generation) return;
    setState(() {
      _loading = false;
      if (reasons.isFailure || cases.isFailure) {
        _error = 'Support could not be loaded. Try again.';
        return;
      }
      _reasons = widget.sellerOfferId == null ? reasons.valueOrNull! : sellerConductReasons;
      if (_reason == null &&
          _reasons.any((r) => r.code == widget.initialReasonCode)) {
        _reason = widget.initialReasonCode;
      }
      if (_reason != null && !_reasons.any((r) => r.code == _reason)) {
        _reason = null;
      }
      final page = cases.valueOrNull!;
      if (more && page.cursor != null && page.cursor == _cursor) {
        _error = 'Could not load more cases. Try again.';
        return;
      }
      _cursor = page.cursor;
      _cases = more
          ? [
              ..._cases,
              ...page.items.where((c) => !_cases.any((old) => old.id == c.id)),
            ]
          : page.items;
    });
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (_intent == null) {
      if ((_reason == null && !_feedback) || _body.text.trim().length < 10) {
        setState(() {
          _formError = 'Choose a reason and add at least 10 characters.';
          _retryDiscarded = false;
        });
        return;
      }
      _intent = (
        reason: _feedback ? 'general' : _reason!,
        body: '${_feedback ? 'Feedback: $_feedbackType\n' : ''}${_body.text.trim()}$_reference'
          '${_feedback && _includeDevice ? '\n\nApp context: ${kIsWeb ? 'Web' : defaultTargetPlatform.name}; ${widget.seller ? 'seller' : 'buyer'} mode.' : ''}',
        key: LocalMarketplaceRepository.newStoreOperationKey('support'),
        sellerOfferId: _feedback ? null : widget.sellerOfferId,
      );
    }
    final intent = _intent!;
    setState(() {
      _sending = true;
      _formError = null;
      _retryDiscarded = false;
      _ack = null;
    });
    final result = await widget.adapter.submit(
      reason: intent.reason,
      body: intent.body,
      operationKey: intent.key,
      sellerOfferId: intent.sellerOfferId,
    );
    if (!mounted) return;
    if (result.isSuccess && _screenshots.isNotEmpty) {
      final attached = await widget.adapter.attachScreenshots(caseId: result.valueOrNull!,
        mediaIds: _screenshots, operationKey: '${intent.key}-screenshots');
      if (!mounted) return;
      if (attached.isFailure) {
        setState(() {
          _sending = false;
          _formError = 'Your feedback was saved, but screenshots were not confirmed. Retry to attach them to the same case.';
        });
        return;
      }
    }
    setState(() {
      _sending = false;
      if (result.isFailure) {
        _formError = widget.generalHelp
            ? 'The question was not confirmed. Retry sends the same question safely.'
            : 'The report was not confirmed. Retry sends the same report safely.';
      } else {
        _ack = result.valueOrNull;
        _intent = null;
        _body.clear();
        _screenshots = [];
        _pickerVersion++;
      }
    });
    if (result.isSuccess) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return SingleChildScrollView(
      padding: metrics.geometryInsets(const EdgeInsets.all(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BuyerNestedHeader(
            title: widget.generalHelp ? 'Help & feedback' : 'Safety report',
            subtitle: widget.generalHelp
                ? 'Ask for help or share an idea.'
                : 'Report an unsafe interaction and track the response.',
            onBack: widget.onBack,
          ),
          SizedBox(height: metrics.spacing(12)),
          if (!_feedback) const BuyerStateNotice(
            icon: Icons.support_agent_outlined,
            tone: BuyerNoticeTone.brand,
            title: 'Support is here to help',
            body:
                'Send a concern to Hocalist support and check the response '
                'here. For immediate danger, contact local emergency services.',
          ),
          SizedBox(height: metrics.spacing(14)),
          if (widget.generalHelp) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final feedback in [false, true]) HocalistFilterChip(
                role: widget.seller ? HocalistControlRole.seller : HocalistControlRole.buyer,
                label: feedback ? 'Send feedback' : 'Get help', selected: _feedback == feedback,
                onSelected: (_) { if (!_sending && _intent == null) setState(() => _feedback = feedback); },
              ),
            ]),
            const SizedBox(height: 12),
            if (_feedback) Wrap(spacing: 8, children: [
              for (final type in ['Problem', 'Suggestion']) HocalistFilterChip(
                role: widget.seller ? HocalistControlRole.seller : HocalistControlRole.buyer, label: type,
                selected: _feedbackType == type,
                onSelected: (_) { if (!_sending && _intent == null) setState(() => _feedbackType = type); }),
            ]),
          ],
          if (widget.conversationId != null) ...[
            Container(
              padding: metrics.geometryInsets(const EdgeInsets.all(12)),
              decoration: BoxDecoration(
                color: HocalistPalette.surface(
                  context,
                  BuyerUiTokens.softSurface,
                ),
                borderRadius: BorderRadius.circular(metrics.geometry(14)),
                border: Border.all(
                  color: HocalistPalette.border(
                    context,
                    const Color(0xffd9d5ff),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BuyerStatusChip(
                    label: 'Reporting this conversation',
                    icon: Icons.chat_bubble_outline_rounded,
                    tone: BuyerNoticeTone.brand,
                  ),
                  SizedBox(height: metrics.spacing(6)),
                  SelectableText(
                    widget.conversationId!,
                    key: const Key('supportConversation'),
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.cardTitle,
                    ).copyWith(fontSize: metrics.fontSize(13)),
                  ),
                  SizedBox(height: metrics.spacing(4)),
                  Text(
                    'The reference is included with your report. Messages and '
                    'photos are not attached automatically.',
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.secondaryBody,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: metrics.spacing(14)),
          ],
          if (_loading) ...[
            const BuyerProgressStrip(label: 'Loading support…'),
            SizedBox(height: metrics.spacing(12)),
          ],
          if (_error != null) ...[
            BuyerStateNotice(
              key: const Key('supportError'),
              icon: Icons.cloud_off_rounded,
              tone: BuyerNoticeTone.error,
              title: 'Support could not be loaded',
              body: _error,
              actionLabel: 'Retry',
              onAction: _loading ? null : () => _load(),
            ),
            SizedBox(height: metrics.spacing(12)),
          ],
          if (_ack != null) ...[
            BuyerStateNotice(
              key: const Key('supportAcknowledged'),
              icon: Icons.task_alt_rounded,
              tone: BuyerNoticeTone.success,
              title: widget.generalHelp
                  ? (_feedback ? 'Feedback received' : 'Question received')
                  : 'Report received',
              body: 'Case ID: $_ack',
            ),
            SizedBox(height: metrics.spacing(12)),
          ],
          if (_formError != null) ...[
            BuyerStateNotice(
              key: const Key('supportFormError'),
              icon: _retryDiscarded
                  ? Icons.info_outline_rounded
                  : Icons.report_outlined,
              tone: _retryDiscarded
                  ? BuyerNoticeTone.warning
                  : BuyerNoticeTone.error,
              title: _retryDiscarded
                  ? 'Retry discarded'
                  : _intent != null
                  ? (widget.generalHelp
                        ? 'Question not confirmed'
                        : 'Report not confirmed')
                  : (widget.generalHelp
                        ? 'Check your question'
                        : 'Check your report'),
              body: _formError,
            ),
            SizedBox(height: metrics.spacing(12)),
          ],
          if (!_feedback) BuyerSecondaryButton(
            label:
                _reasons.where((r) => r.code == _reason).firstOrNull?.label ??
                (widget.generalHelp
                    ? 'Select help topic'
                    : 'Select report reason'),
            onPressed: _sending || _intent != null
                ? null
                : () async {
                    final selected = await showModalBottomSheet<String>(
                      context: context,
                      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (sheet) {
                        final title = widget.generalHelp ? 'Help topic' : 'Report reason';
                        const subtitle = 'Choose the reason that best fits';
                        final options = Column(children: [
                          for (final reason in _reasons)
                            HocalistSheetChoice(
                              seller: widget.seller,
                              label: reason.label,
                              selected: _reason == reason.code,
                              onTap: () => Navigator.pop(sheet, reason.code),
                            ),
                        ]);
                        void close() => Navigator.pop(sheet);
                        return AccountModalSheet(seller: widget.seller, title: title,
                          subtitle: subtitle, icon: Icons.support_agent_rounded,
                          onClose: close, child: options);
                      },
                    );
                    if (mounted && selected != null) {
                      setState(() => _reason = selected);
                    }
                  },
          ),
          SizedBox(height: metrics.spacing(12)),
          HocalistAccountField(
            fieldKey: const Key('supportBody'),
            seller: widget.seller,
            label: _feedback ? 'Your feedback' : 'Your message',
            controller: _body,
            readOnly: _sending || _intent != null,
            maxLength: 3700 - _reference.length,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            hintText: _feedback ? 'What happened, or what could be better?'
                  : widget.generalHelp
                  ? 'How can we help? Include any useful request or account details.'
                  : 'What happened? Include the relevant request or meeting reference.',
          ),
          SizedBox(height: metrics.spacing(10)),
          if (_feedback) ...[
            if (configuredImageUpload('report') case final upload?)
              PrivateImagePicker(key: ValueKey('feedback-photos-$_pickerVersion'),
                upload: upload, maxImages: 3, storePhotoControls: true,
                showGuidance: false, secondaryAction: true,
                addLabel: 'Attach screenshot (optional)',
                role: widget.seller ? HocalistControlRole.seller : HocalistControlRole.buyer,
                enabled: !_sending && _intent == null,
                onPendingChanged: (v) { if (mounted) setState(() => _uploadPending = v); },
                onChanged: (ids) => setState(() => _screenshots = ids)),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Include app context', style: BuyerTypography.style(
                context, metrics, BuyerTextRole.primaryBody)),
              subtitle: Text('Platform and buyer or seller mode only.',
                style: BuyerTypography.style(context, metrics, BuyerTextRole.secondaryBody)),
              value: _includeDevice,
              onChanged: _sending || _intent != null ? null : (v) => setState(() => _includeDevice = v ?? false)),
            const SizedBox(height: 12),
          ],
          AccountActionButton(
            seller: widget.seller,
            onPressed: _loading || _sending || _uploadPending ? null : _submit,
            label: _sending
                ? 'Submitting…'
                : _intent != null
                ? (_feedback ? 'Retry feedback' : widget.generalHelp ? 'Retry question' : 'Retry report')
                : _feedback ? 'Send feedback' : widget.generalHelp
                ? 'Send question'
                : 'Send report',
          ),
          if (_intent != null && !_sending) ...[
            SizedBox(height: metrics.spacing(6)),
            BuyerSecondaryButton(
              label: 'Discard retry',
              onPressed: () {
                setState(() {
                  _intent = null;
                  _retryDiscarded = true;
                  _formError =
                      'Retry discarded. Refresh your cases before sending another report; the previous submission may have succeeded.';
                });
              },
            ),
          ],
          SizedBox(height: metrics.spacing(18)),
          HocalistSectionIntro(
            title: 'Your cases',
            icon: Icons.inbox_outlined,
            trailing: PullRefreshAction(
              onRefresh: _loading ? null : () => _load(),
            ),
          ),
          if (!_loading && _error == null && _cases.isEmpty)
            const BuyerStateNotice(
              icon: Icons.inbox_outlined,
              tone: BuyerNoticeTone.neutral,
              title: 'No reports submitted yet.',
              body: 'Cases you send will appear here with their status.',
            ),
          for (final c in _cases)
            Padding(
              padding: EdgeInsets.only(bottom: metrics.spacing(10)),
              child: Container(
                padding: metrics.geometryInsets(const EdgeInsets.all(14)),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(
                    context,
                    BuyerUiTokens.surface,
                  ),
                  borderRadius: BorderRadius.circular(metrics.geometry(14)),
                  border: Border.all(
                    color: HocalistPalette.border(
                      context,
                      BuyerUiTokens.border,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            c.reason,
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.cardTitle,
                            ).copyWith(fontSize: metrics.fontSize(13.5)),
                          ),
                        ),
                        SizedBox(width: metrics.spacing(8)),
                        Flexible(
                          child: BuyerStatusChip(
                            label: c.status.replaceAll('_', ' '),
                            tone: c.status == 'open'
                                ? BuyerNoticeTone.brand
                                : BuyerNoticeTone.neutral,
                            icon: c.status == 'open'
                                ? Icons.hourglass_top_rounded
                                : Icons.check_circle_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: metrics.spacing(6)),
                    SelectableText(
                      'Case ${c.id}',
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.metadata,
                      ),
                    ),
                    SizedBox(height: metrics.spacing(6)),
                    Text(
                      c.body,
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.primaryBody,
                      ),
                    ),
                    if (c.response != null) ...[
                      SizedBox(height: metrics.spacing(8)),
                      Container(
                        padding: metrics.geometryInsets(
                          const EdgeInsets.all(10),
                        ),
                        decoration: BoxDecoration(
                          color: HocalistPalette.surface(
                            context,
                            BuyerUiTokens.softSurface,
                          ),
                          borderRadius: BorderRadius.circular(
                            metrics.geometry(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Support response',
                              style: BuyerTypography.style(
                                context,
                                metrics,
                                BuyerTextRole.cardTitle,
                              ).copyWith(fontSize: metrics.fontSize(12)),
                            ),
                            SizedBox(height: metrics.spacing(4)),
                            Text(
                              c.response!,
                              style: BuyerTypography.style(
                                context,
                                metrics,
                                BuyerTextRole.primaryBody,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_cursor != null) ...[
            SizedBox(height: metrics.spacing(4)),
            BuyerSecondaryButton(
              label: 'Load more cases',
              onPressed: _loading ? null : () => _load(more: true),
            ),
          ],
        ],
      ),
    );
  }
}

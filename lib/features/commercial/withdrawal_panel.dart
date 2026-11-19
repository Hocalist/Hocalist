import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_motion.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/phase2/commercial/withdrawal_backend.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';

/// Provider-neutral withdrawal panel for the buyer rewards surfaces.
///
/// The authoritative load supplies the minimum, fee, balances and request
/// states. The net amount is shown before confirmation; success is only
/// acknowledged after the server accepts the intent. No payout is simulated.
class WithdrawalPanel extends StatefulWidget {
  const WithdrawalPanel({required this.load, required this.submit, this.verifyContact, this.verificationForm, this.destination, this.destinationReady = true, this.requestsEnabled = true, super.key});

  final Future<void> Function(BuildContext, {required bool phone})? verifyContact;
  final Widget Function(bool phone, VoidCallback verified)? verificationForm;
  final Widget? destination;
  final bool destinationReady, requestsEnabled;
  final Future<WithdrawalStatusView> Function() load;
  final Future<WithdrawalRequestView> Function(
    int amountMinor,
    String operationKey,
  )
  submit;

  @override
  State<WithdrawalPanel> createState() => _WithdrawalPanelState();
}

class _WithdrawalPanelState extends State<WithdrawalPanel> {
  final amount = TextEditingController();
  WithdrawalStatusView? status;
  bool busy = true;
  bool submitting = false;
  String? error;
  String? submitError;
  String? operationKey;
  int? operationAmount;
  int generation = 0;
  bool prompted = false;
  bool verifying = false;

  Future<void> verify(bool phone) async {
    final open = widget.verifyContact;
    if (!mounted || verifying || open == null) return;
    verifying = true;
    try {
      await open(context, phone: phone);
      if (mounted) await refresh();
    } finally {
      verifying = false;
    }
  }

  int? get enteredMinor {
    final text = amount.text.trim();
    if (!RegExp(r'^\d+(?:\.\d{0,2})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    return int.tryParse(parts.first + (parts.length == 2 ? parts.last : '').padRight(2, '0'));
  }

  static String usd(int cents) =>
      '\$${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    generation++;
    amount.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final run = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.load();
      if (!mounted || run != generation) return;
      setState(() => status = value);
      if (!value.phoneVerified && !prompted && widget.verifyContact != null) {
        prompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) unawaited(verify(true)); });
      }
    } catch (_) {
      if (!mounted || run != generation) return;
      setState(() => error = 'Withdrawal status could not be loaded.');
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  Future<void> request() async {
    if (submitting) return;
    final current = status;
    if (!widget.requestsEnabled || current == null || !current.contactVerified || !widget.destinationReady) return;
    final parsed = enteredMinor;
    if (parsed == null || parsed < current.minimumMinor) {
      setState(
        () => submitError = 'Enter at least ${usd(current.minimumMinor)}.',
      );
      return;
    }
    if (parsed > current.availableMinor) {
      setState(
        () => submitError =
            'That is more than your available ${usd(current.availableMinor)}.',
      );
      return;
    }
    if (operationKey == null || operationAmount != parsed) {
      operationKey = UniqueKey().toString();
      operationAmount = parsed;
    }
    setState(() {
      submitting = true;
      submitError = null;
    });
    try {
      final created = await widget.submit(parsed, operationKey!);
      if (!mounted) return;
      operationKey = null;
      operationAmount = null;
      amount.clear();
      setState(() {
        submitting = false;
        status = WithdrawalStatusView(
          minimumMinor: current.minimumMinor,
          feeMinor: current.feeMinor,
          earnedMinor: current.earnedMinor,
          processingMinor: current.processingMinor + created.amountMinor,
          availableMinor: current.availableMinor - created.amountMinor,
          emailVerified: current.emailVerified,
          phoneVerified: current.phoneVerified,
          requests: [created, ...current.requests],
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Withdrawal submitted for processing. '
            'Net payout ${usd(created.netMinor)}.',
          ),
        ),
      );
      if (widget.verificationForm != null) Navigator.of(context).pop(true);
    } on WithdrawalUnavailableException catch (failure) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError = failure.message;
        if (!failure.outcomeUncertain) {
          operationKey = null;
          operationAmount = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        submitError =
            'The withdrawal could not be confirmed. Retry to check it safely.';
      });
    }
  }

  String statusLabel(WithdrawalRequestView row) => switch (row.status) {
    'processing' => 'Processing - funds reserved',
    'failed' => 'Failed - funds restored',
    'paid' => 'Paid',
    _ => 'Unknown',
  };

  BuyerNoticeTone statusTone(WithdrawalRequestView row) => switch (row.status) {
    'processing' => BuyerNoticeTone.brand,
    'failed' => BuyerNoticeTone.error,
    'paid' => BuyerNoticeTone.success,
    _ => BuyerNoticeTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    final current = status;
    final inSheet = widget.verificationForm != null;
    if (inSheet && current != null && !current.contactVerified && error == null) {
      final phone = !current.phoneVerified;
      return BuyerModalSheet(
        title: phone ? 'Verify your phone' : 'Verify your email',
        icon: phone ? Icons.phone_outlined : Icons.email_outlined,
        onClose: () => Navigator.pop(context),
        child: widget.verificationForm!(phone, () => unawaited(refresh())),
      );
    }
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) const BuyerProgressStrip(label: 'Loading withdrawal status…'),
        if (error != null) ...[
          BuyerStateNotice(
            key: const Key('withdrawalLoadError'),
            icon: Icons.cloud_off_rounded,
            tone: BuyerNoticeTone.error,
            title: 'Withdrawal status unavailable',
            body: error!,
            actionLabel: 'Retry',
            onAction: busy ? null : refresh,
          ),
        ],
        if (current != null) ...[
          if (inSheet)
            Text('Available to withdraw: ${usd(current.availableMinor)}', style: BuyerTypography.style(context, metrics, BuyerTextRole.cardTitle))
          else
            _WithdrawalSummaryCard(status: current),
          SizedBox(height: metrics.spacing(12)),
          if (widget.destination != null && (!inSheet || !widget.destinationReady)) ...[
            widget.destination!,
            SizedBox(height: metrics.spacing(12)),
          ],
          if (!current.contactVerified)
            BuyerStateNotice(
              key: const Key('withdrawalVerificationGate'),
              icon: Icons.verified_user_outlined,
              tone: BuyerNoticeTone.warning,
              title: !current.phoneVerified ? 'Phone verification needed' : 'Email verification needed',
              actionLabel: widget.verifyContact == null ? null : (!current.phoneVerified ? 'Verify phone' : 'Verify email'),
              onAction: widget.verifyContact == null ? null : () => verify(!current.phoneVerified),
              body: !current.phoneVerified ? 'Confirm your phone number to request a withdrawal.' : 'Confirm your email to request a withdrawal.',
            )
          else ...[
            TextField(
              key: const Key('withdrawalAmountField'),
              controller: amount,
              enabled: !submitting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() => submitError = null),
              decoration:
                  buyerInputDecoration(
                    context,
                    hintText: '0.00',
                    prefixIcon: Icon(
                      Icons.payments_outlined,
                      color: HocalistPalette.text(
                        context,
                        BuyerUiTokens.action,
                      ),
                    ),
                  ).copyWith(
                    labelText: 'Withdrawal amount',
                    prefixText: r'$ ',
                    helperText: 'Minimum ${usd(current.minimumMinor)}',
                  ),
            ),
            if (enteredMinor case final parsed?) ...[
              SizedBox(height: metrics.spacing(8)),
              Container(
                padding: metrics.geometryInsets(const EdgeInsets.all(12)),
                decoration: BoxDecoration(
                  color: HocalistPalette.surface(
                    context,
                    BuyerUiTokens.softSurface,
                  ),
                  borderRadius: BorderRadius.circular(metrics.geometry(13)),
                  border: Border.all(
                    color: HocalistPalette.border(
                      context,
                      const Color(0xffd9d5ff),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    BuyerGlyphIcon(
                      icon: Icons.calculate_outlined,
                      slotSize: metrics.artSize(20),
                      glyphSize: metrics.artSize(20),
                      color: HocalistPalette.text(
                        context,
                        BuyerUiTokens.action,
                      ),
                    ),
                    SizedBox(width: metrics.spacing(8)),
                    Expanded(
                      child: Text(
                        'Net payout after the ${usd(current.feeMinor)} deduction: '
                        '${usd(current.netFor(parsed))}',
                        key: const Key('withdrawalNetAmount'),
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.primaryBody,
                          weight: FontWeight.w700,
                        ).copyWith(fontSize: metrics.fontSize(12.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (submitError != null) ...[
              SizedBox(height: metrics.spacing(8)),
              BuyerStateNotice(
                key: const Key('withdrawalSubmitError'),
                icon: Icons.error_outline_rounded,
                tone: BuyerNoticeTone.error,
                title: 'Withdrawal was not submitted',
                body: submitError,
              ),
            ],
            SizedBox(height: metrics.spacing(10)),
            if (!widget.requestsEnabled)
              const Text('Withdrawal requests are currently unavailable.'),
            BuyerPrimaryButton(
              key: const Key('withdrawalSubmit'),
              onPressed: submitting || busy || !widget.destinationReady || !widget.requestsEnabled || current.availableMinor < current.minimumMinor ? null : request,
              label: submitting ? 'Submitting…' : 'Request withdrawal',
            ),
          ],
          SizedBox(height: metrics.spacing(16)),
          if (!inSheet) ...[
          Row(children: [
            const Expanded(child: BuyerSectionHeading(title: 'Withdrawal history')),
            IconButton(
              key: const Key('withdrawalRefresh'),
              tooltip: 'Refresh withdrawal status',
              onPressed: busy || submitting ? null : refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ]),
          if (current.requests.isEmpty)
            const BuyerStateNotice(
              icon: Icons.receipt_long_outlined,
              tone: BuyerNoticeTone.neutral,
              title: 'No withdrawals yet',
              body:
                  'Your requests will appear here.',
            )
          else
            for (final row in current.requests)
              Padding(
                padding: EdgeInsets.only(bottom: metrics.spacing(8)),
                child: Container(
                  padding: metrics.geometryInsets(const EdgeInsets.all(13)),
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
                      Text(
                        '${usd(row.amountMinor)} gross · '
                        '${usd(row.netMinor)} net',
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.cardTitle,
                        ).copyWith(fontSize: metrics.fontSize(13)),
                      ),
                      SizedBox(height: metrics.spacing(6)),
                      Wrap(
                        spacing: metrics.spacing(8),
                        runSpacing: metrics.spacing(4),
                        children: [
                          BuyerStatusChip(
                            key: Key('withdrawal-${row.id}'),
                            label: statusLabel(row),
                            tone: statusTone(row),
                            icon: statusTone(row) == BuyerNoticeTone.success
                                ? Icons.check_circle_rounded
                                : statusTone(row) == BuyerNoticeTone.error
                                ? Icons.error_outline_rounded
                                : Icons.schedule_rounded,
                          ),
                        ],
                      ),
                      if (row.failureReason != null) ...[
                        SizedBox(height: metrics.spacing(5)),
                        Text(
                          row.failureReason!,
                          style: BuyerTypography.style(
                            context,
                            metrics,
                            BuyerTextRole.secondaryBody,
                            color: const Color(0xffc62828),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          SizedBox(height: metrics.spacing(8)),
          ],
        ],
      ],
    );
    if (!inSheet) return content;
    return PopScope(
      canPop: !submitting,
      child: BuyerModalSheet(
      title: 'Withdraw rewards',
      icon: Icons.account_balance_wallet_outlined,
      onClose: () { if (!submitting) Navigator.pop(context); },
      child: content,
      ),
    );
  }
}

class _WithdrawalSummaryCard extends StatelessWidget {
  const _WithdrawalSummaryCard({required this.status});

  final WithdrawalStatusView status;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return HocalistEntrance(child: Container(
      padding: metrics.geometryInsets(const EdgeInsets.all(18)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, BuyerUiTokens.softSurface),
        borderRadius: BorderRadius.circular(metrics.geometry(18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Available to withdraw', style: Theme.of(context).textTheme.titleSmall),
            Text(_WithdrawalPanelState.usd(status.availableMinor),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800, color: HocalistPalette.text(context, BuyerUiTokens.action))),
          ])),
          BuyerAssetIconSurface(asset: 'assets/approved_onboarding_home/dashboard-trophy-glyph.png',
            surfaceSize: metrics.artSize(58), iconSize: metrics.artSize(36),
            backgroundColor: HocalistPalette.surface(context, const Color(0xffe9e4ff)),
            shape: BuyerIconSurfaceShape.circle),
        ]),
        const Divider(height: 26),
        Wrap(spacing: 20, runSpacing: 6, children: [
          Text('Minimum ${_WithdrawalPanelState.usd(status.minimumMinor)}'),
          Text('Fee ${_WithdrawalPanelState.usd(status.feeMinor)}'),
          if (status.processingMinor > 0) Text('Processing ${_WithdrawalPanelState.usd(status.processingMinor)}'),
        ]),
      ]),
    ));
  }
}

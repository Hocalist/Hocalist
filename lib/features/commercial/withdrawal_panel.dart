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
  const WithdrawalPanel({required this.load, required this.submit, super.key});

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
    if (current == null) return;
    final parsed = int.tryParse(amount.text.trim());
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
    return Column(
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
          _WithdrawalSummaryCard(status: current),
          SizedBox(height: metrics.spacing(12)),
          if (!current.contactVerified)
            BuyerStateNotice(
              key: const Key('withdrawalVerificationGate'),
              icon: Icons.verified_user_outlined,
              tone: BuyerNoticeTone.warning,
              title: 'Verify your contacts to withdraw',
              body:
                  'Verify your email and phone before withdrawing. '
                  'Email verified: ${current.emailVerified ? 'yes' : 'no'}; '
                  'phone verified: ${current.phoneVerified ? 'yes' : 'no'}.',
            )
          else ...[
            TextField(
              key: const Key('withdrawalAmountField'),
              controller: amount,
              enabled: !submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => submitError = null),
              decoration:
                  buyerInputDecoration(
                    context,
                    hintText: 'Amount in cents',
                    prefixIcon: Icon(
                      Icons.payments_outlined,
                      color: HocalistPalette.text(
                        context,
                        BuyerUiTokens.action,
                      ),
                    ),
                  ).copyWith(
                    labelText: 'Withdrawal amount (cents)',
                    helperText: 'Minimum ${usd(current.minimumMinor)}',
                  ),
            ),
            if (int.tryParse(amount.text.trim()) case final parsed?) ...[
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
            BuyerPrimaryButton(
              key: const Key('withdrawalSubmit'),
              onPressed: submitting || busy ? null : request,
              label: submitting ? 'Submitting…' : 'Request withdrawal',
            ),
          ],
          SizedBox(height: metrics.spacing(16)),
          const BuyerSectionHeading(title: 'Withdrawal history'),
          if (current.requests.isEmpty)
            const BuyerStateNotice(
              icon: Icons.receipt_long_outlined,
              tone: BuyerNoticeTone.neutral,
              title: 'No withdrawal requests yet.',
              body:
                  'Requested payouts and their provider status will appear here.',
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
          SizedBox(height: metrics.spacing(6)),
          BuyerSecondaryButton(
            key: const Key('withdrawalRefresh'),
            label: 'Refresh withdrawal status',
            onPressed: busy || submitting ? null : refresh,
          ),
          SizedBox(height: metrics.spacing(8)),
          Text(
            'Withdrawals are provider-neutral and reviewed before payout. '
            'A processing request reserves the amount; a confirmed failure '
            'restores it.',
            style: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.secondaryBody,
            ),
          ),
        ],
      ],
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
    return HocalistEntrance(
      child: Container(
        padding: metrics.geometryInsets(const EdgeInsets.all(16)),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xfff4f2ff), Color(0xffeeedff)],
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(18)),
          border: Border.all(
            color: HocalistPalette.border(context, const Color(0xffd9d5ff)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: metrics.artSize(34),
                  height: metrics.artSize(34),
                  decoration: BoxDecoration(
                    color: HocalistPalette.surface(context, Colors.white),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: BuyerGlyphIcon(
                      icon: Icons.account_balance_rounded,
                      slotSize: metrics.artSize(19),
                      glyphSize: metrics.artSize(19),
                      color: HocalistPalette.text(
                        context,
                        BuyerUiTokens.action,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: metrics.spacing(10)),
                Expanded(
                  child: Text(
                    'Available to withdraw',
                    style: BuyerTypography.style(
                      context,
                      metrics,
                      BuyerTextRole.cardTitle,
                    ).copyWith(fontSize: metrics.fontSize(12.5)),
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.spacing(10)),
            Text(
              _WithdrawalPanelState.usd(status.availableMinor),
              key: const Key('withdrawalAvailable'),
              style: BuyerTypography.style(
                context,
                metrics,
                BuyerTextRole.displayTitle,
                weight: FontWeight.w900,
              ).copyWith(fontSize: metrics.fontSize(26)),
            ),
            SizedBox(height: metrics.spacing(12)),
            Wrap(
              spacing: metrics.spacing(18),
              runSpacing: metrics.spacing(10),
              children: [
                BuyerMetricTile(
                  label: 'Earned',
                  value: _WithdrawalPanelState.usd(status.earnedMinor),
                ),
                BuyerMetricTile(
                  label: 'Reserved',
                  value: _WithdrawalPanelState.usd(status.processingMinor),
                  valueKey: const Key('withdrawalProcessing'),
                ),
                BuyerMetricTile(
                  label: 'Minimum',
                  value: _WithdrawalPanelState.usd(status.minimumMinor),
                ),
                BuyerMetricTile(
                  label: 'Fee',
                  value: _WithdrawalPanelState.usd(status.feeMinor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

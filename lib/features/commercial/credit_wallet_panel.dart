import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_reload_link.dart';
import '../../components/hocalist_motion.dart';
import '../../components/hocalist_section_tabs.dart';
import 'package:flutter/material.dart';

import '../../data/phase2/commercial/commercial_wallet_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/seller_ui_foundation.dart';
import 'seller_payment_panel.dart';

/// Seller credit wallet over the authoritative ledger read.
///
/// Every amount, rate and quota value comes from `commercial_credit_wallet`;
/// the panel never computes availability locally and never enables a purchase
/// it cannot complete. A missing loader, missing bundle or failed read renders
/// an explicit unavailable/error state instead of a fabricated balance.
class CreditWalletPanel extends StatefulWidget {
  const CreditWalletPanel({this.load, this.additionalSections, super.key});

  final Future<CreditWalletView> Function()? load;
  final Map<String, List<Widget>>? additionalSections;

  @override
  State<CreditWalletPanel> createState() => _CreditWalletPanelState();
}

String _hc(int minor) =>
    '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')} HC';

String _targetLabel(CreditTargetStatus status) => switch (status) {
  CreditTargetStatus.reserved => 'Reserved — awaiting qualification',
  CreditTargetStatus.initialCharged => 'Initial fee charged',
  CreditTargetStatus.won => 'Won — full fee charged',
  CreditTargetStatus.released => 'Released',
  CreditTargetStatus.refunded => 'Refunded',
};

SellerNoticeTone _targetTone(CreditTargetStatus status) => switch (status) {
  CreditTargetStatus.reserved => SellerNoticeTone.brand,
  CreditTargetStatus.initialCharged => SellerNoticeTone.warning,
  CreditTargetStatus.won => SellerNoticeTone.success,
  CreditTargetStatus.released => SellerNoticeTone.neutral,
  CreditTargetStatus.refunded => SellerNoticeTone.neutral,
};

class _CreditWalletPanelState extends State<CreditWalletPanel> {
  CreditWalletView? data;
  String? error;
  bool loading = true;
  int generation = 0;

  Widget get refresh => HocalistReloadLink(
    key: const Key('creditWalletRefresh'),
    description: 'Reload credits',
    loading: loading,
    onPressed: load,
    color: SellerUiColors.primaryBright,
  );

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<CreditWalletView> _defaultLoad() async {
    final backend = createConfiguredCommercialWalletBackend();
    if (backend == null) {
      throw const CommercialUnavailableException(
        'Credits are not available in this build yet.',
      );
    }
    return backend.loadCreditWallet();
  }

  Future<void> load() async {
    final run = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await (widget.load ?? _defaultLoad)();
      if (!mounted || run != generation) return;
      setState(() => data = value);
    } catch (_) {
      if (mounted && run == generation) {
        setState(() => error = 'Credits could not be loaded. Please retry.');
      }
    } finally {
      if (mounted && run == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = data;
    return Column(
      key: const Key('creditWalletPanel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading) const SellerProgressStrip(label: 'Loading your credits…'),
        if (error != null) ...[
          SellerStateNotice(
            key: const Key('creditWalletError'),
            icon: Icons.cloud_off_rounded,
            title: error!,
            body: 'Your ledger is unchanged. Retry when you are online.',
            tone: SellerNoticeTone.error,
          ),
          const SizedBox(height: 8),
        ],
        if (widget.additionalSections != null)
          HocalistSectionTabs(
            accent: SellerUiColors.primaryBright,
            sections: {
              'Credits': [
                if (value != null)
                  _WalletBody(
                    value: value,
                    section: _WalletSection.credits,
                    reload: refresh,
                  )
                else
                  SellerStateNotice(
                    icon: Icons.account_balance_wallet_outlined,
                    title: loading ? 'Loading credits…' : 'Credits unavailable',
                    body: 'Your balance appears after the ledger is read.',
                  ),
                if (value == null) refresh,
              ],
              'Activity': [
                if (value != null)
                  _WalletBody(
                    value: value,
                    section: _WalletSection.targeting,
                    reload: refresh,
                  )
                else
                  SellerStateNotice(
                    icon: Icons.history_rounded,
                    title: loading
                        ? 'Loading targeting activity…'
                        : 'Targeting activity unavailable',
                    body: 'Activity appears after the ledger is read.',
                  ),
                if (value == null) refresh,
              ],
              ...widget.additionalSections!,
            },
          )
        else if (value != null)
          _WalletBody(value: value, reload: refresh),
        if (widget.additionalSections == null && value == null) refresh,
        if (value == null && !loading && error == null)
          const SellerStateNotice(
            key: Key('creditWalletUnavailable'),
            icon: Icons.hourglass_empty_rounded,
            title: 'Credit wallet unavailable',
            body:
                'Nothing is shown until the authoritative ledger can be read.',
            tone: SellerNoticeTone.neutral,
          ),
      ],
    );
  }
}

enum _WalletSection { all, credits, targeting }

class _WalletBody extends StatelessWidget {
  const _WalletBody({
    required this.value,
    required this.reload,
    this.section = _WalletSection.all,
  });
  final Widget reload;

  final CreditWalletView value;
  final _WalletSection section;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 360;
    final capacity = value.weekly.limit <= 0
        ? 0.0
        : (value.weekly.used / value.weekly.limit).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section != _WalletSection.targeting) ...[
          SellerStateNotice(
            key: const Key('creditWalletBalanceCard'),
            icon: Icons.account_balance_wallet_rounded,
            title: 'Available credits',
            body:
                'Prepaid HocaCredits fund targeting fees. Oldest eligible credits '
                'are used first.',
            tone: SellerNoticeTone.brand,
            detail: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hc(value.availableMinor),
                  key: const Key('creditWalletAvailable'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sellerText(
                    metrics ?? _fallbackMetrics(context),
                    24,
                    weight: FontWeight.w800,
                    color: SellerUiColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    SellerMetricTile(
                      key: const Key('creditWalletTotal'),
                      label: 'Total',
                      value: _hc(value.balanceMinor),
                    ),
                    SellerMetricTile(
                      key: const Key('creditWalletReserved'),
                      label: 'Reserved',
                      value: _hc(value.reservedMinor),
                    ),
                    SellerMetricTile(
                      key: const Key('creditWalletCharged'),
                      label: 'Charged to date',
                      value: _hc(value.chargedMinor),
                    ),
                    SellerMetricTile(
                      key: const Key('creditWalletDeposited'),
                      label: 'Deposited to date',
                      value: _hc(value.depositedMinor),
                    ),
                    if (value.reversalHoldMinor > 0)
                      SellerMetricTile(
                        key: const Key('creditWalletReversalHold'),
                        label: 'Reversal holds',
                        value: _hc(value.reversalHoldMinor),
                        tone: SellerNoticeTone.warning,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SellerStateNotice(
            key: const Key('creditWalletWeekly'),
            icon: Icons.track_changes_rounded,
            title: 'Weekly targeting capacity',
            body:
                'This allowance is separate from your prepaid credits. '
                'A winning adjustment never consumes another slot.',
            tone: SellerNoticeTone.neutral,
            trailing: Text(
              '${value.weekly.used} / ${value.weekly.limit}',
              key: const Key('creditWalletWeeklyUsed'),
              style: sellerText(
                metrics ?? _fallbackMetrics(context),
                18,
                weight: FontWeight.w800,
                color: SellerUiColors.ink,
              ),
            ),
            detail: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Semantics(
                    container: true,
                    child: LinearProgressIndicator(
                      semanticsLabel:
                          'Weekly targeting capacity, ${value.weekly.used} of ${value.weekly.limit} used',
                      value: capacity,
                      minHeight: 6,
                      backgroundColor: HocalistPalette.surface(
                        context,
                        SellerUiColors.lavender,
                      ),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        SellerUiColors.primaryBright,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${value.weekly.remaining} remaining this week',
                  style: sellerText(
                    metrics ?? _fallbackMetrics(context),
                    12,
                    color: SellerUiColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DepositBatchDetails(value: value, compact: compact),
          const SizedBox(height: 14),
          _CreditPackDetails(value: value),
        ],
        if (section != _WalletSection.credits) ...[
          const SizedBox(height: 14),
          _TargetActivity(value: value, compact: compact),
        ],
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              'Item payment stays offline. HocaCredits pay targeting fees only.',
              style: sellerText(
                metrics ?? _fallbackMetrics(context),
                12,
                color: SellerUiColors.muted,
              ),
            ),
            reload,
          ],
        ),
      ],
    );
  }

  static ApprovedReplicaMetrics _fallbackMetrics(BuildContext context) {
    final media = MediaQuery.of(context);
    return ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: media.size.width,
      textScaler: media.textScaler,
    );
  }
}

class _CreditPackDetails extends StatefulWidget {
  const _CreditPackDetails({required this.value});
  final CreditWalletView value;
  @override
  State<_CreditPackDetails> createState() => _CreditPackDetailsState();
}

class _CreditPackDetailsState extends State<_CreditPackDetails> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SellerSectionHeading(
        title: 'Credit packs',
        actionKey: const Key('creditPacksToggle'),
        actionLabel: expanded ? 'Hide details' : 'View details',
        onAction: () => setState(() => expanded = !expanded),
      ),
      HocalistExpand(
        child: expanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.value.depositOptionsConfigured)
                    const SellerStateNotice(
                      key: Key('creditWalletNoPacks'),
                      icon: Icons.storefront_outlined,
                      title: 'No credit packs available',
                      body: 'Available packs will appear here.',
                    )
                  else ...[
                    for (final option in widget.value.depositOptions)
                      _OptionCard(option: option),
                    const SellerPaymentPanel(creditPurchase: true),
                  ],
                ],
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _TargetActivity extends StatelessWidget {
  const _TargetActivity({required this.value, required this.compact});
  final CreditWalletView value;
  final bool compact;
  @override
  Widget build(BuildContext context) => HocalistSectionTabs(
    accent: SellerUiColors.primaryBright,
    sections: {
      'Recent': _cards(value.targets),
      'Reserved': _cards(
        value.targets.where((t) => t.reservedMinor > 0).toList(),
      ),
      'Charged': _cards(
        value.targets.where((t) => t.chargedMinor > 0).toList(),
      ),
    },
  );
  List<Widget> _cards(List<CreditTargetView> targets) => targets.isEmpty
      ? [
          const SellerStateNotice(
            key: Key('creditWalletNoTargets'),
            icon: Icons.history_rounded,
            title: 'No activity here yet',
            body: 'Matching targeting fees will appear here.',
          ),
        ]
      : [
          for (final target in targets)
            _TargetCard(target: target, compact: compact),
        ];
}

class _DepositBatchDetails extends StatefulWidget {
  const _DepositBatchDetails({required this.value, required this.compact});
  final CreditWalletView value;
  final bool compact;
  @override
  State<_DepositBatchDetails> createState() => _DepositBatchDetailsState();
}

class _DepositBatchDetailsState extends State<_DepositBatchDetails> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SellerSectionHeading(
        title: 'Deposit details',
        actionKey: const Key('creditDepositDetailsToggle'),
        actionLabel: expanded ? 'Hide details' : 'View details',
        onAction: () => setState(() => expanded = !expanded),
      ),
      HocalistExpand(
        child: expanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.value.batches.isEmpty)
                    const SellerStateNotice(
                      icon: Icons.inventory_2_outlined,
                      title: 'No deposits yet',
                      body: 'Deposits and their fixed rates appear here.',
                    )
                  else
                    for (final batch in widget.value.batches)
                      _BatchCard(batch: batch, compact: widget.compact),
                ],
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch, required this.compact});

  final CreditBatchView batch;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? _fallback(context);
    return HocalistEntrance(
      child: Container(
        key: Key('creditBatch-${batch.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HocalistPalette.surface(context, SellerUiColors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: HocalistPalette.border(context, SellerUiColors.line),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Deposited ${_hc(batch.originalMinor)}',
                    style: sellerText(
                      metrics,
                      14,
                      weight: FontWeight.w800,
                      color: SellerUiColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: SellerStatusChip(
                    label: 'Deposit pricing',
                    icon: Icons.lock_outline_rounded,
                    tone: SellerNoticeTone.brand,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                SellerMetricTile(
                  label: 'Available',
                  value: _hc(batch.availableMinor),
                ),
                SellerMetricTile(
                  label: 'Reserved',
                  value: _hc(batch.reservedMinor),
                ),
                SellerMetricTile(
                  label: 'Remaining',
                  value: _hc(batch.balanceMinor),
                ),
                SellerMetricTile(
                  label: 'Charged',
                  value: _hc(batch.chargedMinor),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Immutable batch rates: initial '
              '${_hc(batch.initialFeeMinor)} · winning total '
              '${_hc(batch.winningTotalMinor)}',
              style: sellerText(
                metrics,
                compact ? 11 : 12,
                color: SellerUiColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ApprovedReplicaMetrics _fallback(BuildContext context) {
    final media = MediaQuery.of(context);
    return ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: media.size.width,
      textScaler: media.textScaler,
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option});

  final DepositOptionView option;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? _fallback(context);
    return HocalistEntrance(
      child: Container(
        key: Key('creditOption-${option.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HocalistPalette.surface(context, SellerUiColors.lavender),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: HocalistPalette.border(
              context,
              SellerUiColors.lavenderBorder,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_hc(option.amountMinor)} pack',
                    style: sellerText(
                      metrics,
                      14,
                      weight: FontWeight.w800,
                      color: SellerUiColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: SellerStatusChip(
                    label: 'Pack pricing',
                    tone: SellerNoticeTone.brand,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Initial ${_hc(option.initialFeeMinor)} · '
              'winning total ${_hc(option.winningTotalMinor)}',
              style: sellerText(metrics, 12, color: SellerUiColors.body),
            ),
            const SizedBox(height: 4),
            Text(
              'Checkout confirms these pack rates before payment.',
              style: sellerText(metrics, 11, color: SellerUiColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  static ApprovedReplicaMetrics _fallback(BuildContext context) {
    final media = MediaQuery.of(context);
    return ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: media.size.width,
      textScaler: media.textScaler,
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.target, required this.compact});

  final CreditTargetView target;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? _fallback(context);
    return HocalistEntrance(
      child: Container(
        key: Key('creditTarget-${target.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HocalistPalette.surface(context, SellerUiColors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: HocalistPalette.border(context, SellerUiColors.line),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    target.requestTitle ?? 'Request',
                    style: sellerText(
                      metrics,
                      13,
                      weight: FontWeight.w700,
                      color: SellerUiColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: SellerStatusChip(
                    key: Key('creditTargetStatus-${target.id}'),
                    label: _targetLabel(target.status),
                    tone: _targetTone(target.status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                SellerMetricTile(
                  label: 'Initial',
                  value: _hc(target.initialMinor),
                ),
                SellerMetricTile(
                  label: 'Winning total',
                  value: _hc(target.winningMinor),
                ),
                SellerMetricTile(
                  label: 'Charged',
                  value: _hc(target.chargedMinor),
                ),
                SellerMetricTile(
                  label: 'Reserved',
                  value: _hc(target.reservedMinor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Reserved pricing'
              '${target.qualifiedAt == null ? '' : ' · qualified'}',
              style: sellerText(
                metrics,
                compact ? 11 : 12,
                color: SellerUiColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ApprovedReplicaMetrics _fallback(BuildContext context) {
    final media = MediaQuery.of(context);
    return ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: media.size.width,
      textScaler: media.textScaler,
    );
  }
}

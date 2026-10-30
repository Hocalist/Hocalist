import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_reload_link.dart';
import '../../components/hocalist_motion.dart';
import '../../components/hocalist_section_tabs.dart';
import 'package:flutter/material.dart';

import '../../data/phase2/commercial/commercial_wallet_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/seller_ui_foundation.dart';
import 'seller_payment_panel.dart';
import 'wallet_history_list.dart';

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
  CreditTargetStatus.reserved => 'Reserved',
  CreditTargetStatus.initialCharged => 'Initial fee charged',
  CreditTargetStatus.won => 'Completed',
  CreditTargetStatus.released => 'Released',
  CreditTargetStatus.refunded => 'Refunded',
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
            subtle: true,
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
                const SizedBox(height: 4),
                Text(
                  'Resets ${MaterialLocalizations.of(context).formatMediumDate(value.weekly.resetsAt)} · 00:00 UTC',
                  key: const Key('creditWeeklyReset'),
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
  bool expanded = true;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SellerSectionHeading(
        title: 'Prepaid wallet savings',
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
                    _WalletFeeTable(options: widget.value.depositOptions),
                    const SizedBox(height: 14),
                    const SellerPaymentPanel(
                      creditPurchase: true,
                      compact: true,
                      label: 'Add credits',
                    ),
                  ],
                ],
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _TargetActivity extends StatefulWidget {
  const _TargetActivity({required this.value, required this.compact});
  final CreditWalletView value;
  final bool compact;
  @override
  State<_TargetActivity> createState() => _TargetActivityState();
}

class _TargetActivityState extends State<_TargetActivity> {
  String filter = 'Recent';
  Future<void> chooseFilter() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: HocalistPalette.surface(context, Colors.white),
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filter activity',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close filters',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Show activity',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final choice in ['Recent', 'Reserved', 'Charged'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: HocalistPalette.surface(
                      context,
                      filter == choice ? SellerUiColors.lavender : Colors.white,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(context, choice),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                choice,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              filter == choice
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: SellerUiColors.primaryBright,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && selected != null) setState(() => filter = selected);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              filter,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'Filter activity',
            onPressed: chooseFilter,
            icon: const Icon(
              Icons.tune_rounded,
              color: SellerUiColors.primaryBright,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ..._rows(switch (filter) {
        'Reserved' =>
          widget.value.targets.where((t) => t.reservedMinor > 0).toList(),
        'Charged' =>
          widget.value.targets.where((t) => t.chargedMinor > 0).toList(),
        _ => widget.value.targets,
      }, filter.toLowerCase()),
    ],
  );
  List<Widget> _rows(List<CreditTargetView> targets, String filter) =>
      targets.isEmpty
      ? [
          const SellerStateNotice(
            key: Key('creditWalletNoTargets'),
            icon: Icons.history_rounded,
            title: 'No activity here yet',
            body: 'Matching targeting fees will appear here.',
          ),
        ]
      : [
          WalletHistoryList(
            key: ValueKey('activity-$filter'),
            kind: 'creditTarget-$filter',
            entries: [
              for (final target in targets)
                WalletHistoryEntry(
                  id: target.id,
                  title: target.requestTitle ?? 'Request',
                  date: target.createdAt,
                  amount: _hc(
                    target.chargedMinor > 0
                        ? target.chargedMinor
                        : target.reservedMinor,
                  ),
                  status: _targetLabel(target.status),
                  facts: {
                    'Initial bid': _hc(target.initialMinor),
                    'Winning total': _hc(target.winningMinor),
                    'Total charged': _hc(target.chargedMinor),
                    'Still reserved': _hc(target.reservedMinor),
                  },
                  note:
                      'The winning total includes the initial bid. Your deposit’s saved rates apply.',
                ),
            ],
          ),
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
  bool expanded = true;
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
        child: !expanded
            ? const SizedBox.shrink()
            : widget.value.batches.isEmpty
            ? const SellerStateNotice(
                icon: Icons.inventory_2_outlined,
                title: 'No deposits yet',
                body: 'Deposits and their fixed rates appear here.',
              )
            : WalletHistoryList(
                kind: 'creditBatch',
                entries: [
                  for (final batch in widget.value.batches)
                    WalletHistoryEntry(
                      id: batch.id,
                      title:
                          '${_hc(batch.originalMinor)} ${batch.fundingKind == 'paygo' ? 'funding' : 'deposit'}',
                      date: batch.createdAt,
                      amount: _hc(batch.availableMinor),
                      status: batch.balanceMinor == 0 ? 'Used' : 'Available',
                      facts: {
                        'Deposited': _hc(batch.originalMinor),
                        'Available': _hc(batch.availableMinor),
                        'Reserved': _hc(batch.reservedMinor),
                        'Remaining': _hc(batch.balanceMinor),
                        'Charged': _hc(batch.chargedMinor),
                        'Initial bid': _hc(batch.initialFeeMinor),
                        'Winning total': _hc(batch.winningTotalMinor),
                      },
                      note:
                          'These rates were saved with this deposit and stay attached to its credits.',
                    ),
                ],
              ),
      ),
    ],
  );
}

class _WalletFeeTable extends StatelessWidget {
  const _WalletFeeTable({required this.options});
  final List<DepositOptionView> options;

  @override
  Widget build(BuildContext context) {
    final line = HocalistPalette.border(context, SellerUiColors.line);
    Widget cell(String text, {bool heading = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: heading ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: line),
          verticalInside: BorderSide(color: line),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, const Color(0xFFEAF3FF)),
            ),
            children: [
              cell('Wallet', heading: true),
              cell('Initial bid', heading: true),
              cell('Winning total', heading: true),
            ],
          ),
          for (final option in options)
            TableRow(
              key: ValueKey('creditOption-${option.id}'),
              children: [
                KeyedSubtree(
                  key: ValueKey('creditOption-${option.id}'),
                  child: cell(_hc(option.amountMinor)),
                ),
                cell(_hc(option.initialFeeMinor)),
                cell(_hc(option.winningTotalMinor)),
              ],
            ),
        ],
      ),
    );
  }
}

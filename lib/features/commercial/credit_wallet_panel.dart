import 'package:hocalist/theme/adaptive_palette.dart';
import '../../components/hocalist_reload_link.dart';
import '../../components/hocalist_motion.dart';
import '../../components/hocalist_section_tabs.dart';
import 'package:flutter/material.dart';

import '../../data/phase2/commercial/commercial_wallet_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../components/hocalist_choice_sheet.dart';
import '../../theme/seller_ui_foundation.dart';
import 'seller_payment_panel.dart';
import 'wallet_history_list.dart';
import 'money_help.dart';
import 'seller_offer_presentation.dart';

/// Seller credit wallet over the authoritative ledger read.
///
/// Every amount, rate and quota value comes from `commercial_credit_wallet`;
/// the panel never computes availability locally and never enables a purchase
/// it cannot complete. A missing loader, missing bundle or failed read renders
/// an explicit unavailable/error state instead of a fabricated balance.
class CreditWalletPanel extends StatefulWidget {
  const CreditWalletPanel({this.load, this.additionalSections, this.initialSection, super.key});
  final String? initialSection;

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
            initialSection: widget.initialSection,
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

void _showReservedCredits(BuildContext context, CreditWalletView wallet) {
  final offers = wallet.reservedOffers ?? [
    for (final target in wallet.targets.where((t) => t.reservedMinor > 0))
      ReservedOfferView(target.requestTitle, target.offerId ?? target.requestId,
        target.reservedMinor, target.chargedMinor,
        target.chargedMinor > 0 ? 'remaining_fee' : 'offer_outcome'),
  ];
  final other = wallet.reservedMinor - wallet.reversalHoldMinor -
      offers.fold<int>(0, (sum, offer) => sum + offer.heldMinor);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => SellerModalSheet(
      title: 'Reserved credits',
      subtitle: '${_hc(wallet.reservedMinor)} held in your wallet',
      icon: Icons.account_balance_wallet_outlined,
      onClose: () => Navigator.pop(sheet),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wallet.reservedMinor == 0)
            const Text('You have no credits on hold.')
          else ...[
            for (final offer in offers)
              _CreditHoldRow(title: offer.title ?? 'Offer', amount: offer.heldMinor,
                reference: offer.reference, explanation: switch (offer.nextStep) {
                  'buyer_response' => 'Waiting for the buyer to respond. Unused credits return to your balance when the offer closes.',
                  'payment' => 'These credits are set aside for a targeting fee. Your balance updates when the payment is settled.',
                  'meeting' => 'Your meeting is active. If the sale goes ahead, confirm it with the purchase PIN to settle the fee.',
                  'elite_outcome' => 'Your initial fee is deferred. The purchase outcome or request deadline determines how much is charged or released.',
                  'remaining_fee' => 'The initial fee has been charged. A PIN-confirmed purchase settles the remaining fee. Unused credits return to your balance when the offer closes.',
                  _ => 'These credits cover potential fees for this offer. Any unused amount returns to your balance when the offer is settled.',
                }),
            if (wallet.reversalHoldMinor > 0)
              _CreditHoldRow(title: 'Payment review', amount: wallet.reversalHoldMinor,
                explanation: 'A credit payment is under review. Your balance updates when the review is resolved.'),
            if (other > 0)
              _CreditHoldRow(title: 'Other reserved credits', amount: other,
                explanation: 'The offer details for this amount are currently unavailable.'),
          ],
        ],
      ),
    ),
  );
}

class _CreditHoldRow extends StatelessWidget {
  const _CreditHoldRow({required this.title, required this.amount,
    required this.explanation, this.reference});
  final String title, explanation;
  final int amount;
  final String? reference;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? _WalletBody._fallbackMetrics(context);
    final ref = reference;
    final amountText = Text(_hc(amount), style: sellerText(metrics, 15,
      weight: FontWeight.w800, color: SellerUiColors.primary));
    final name = Text(title, style: sellerText(metrics, 15, weight: FontWeight.w800));
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.white),
        border: Border.all(color: HocalistPalette.border(context, SellerUiColors.lavenderBorder)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, bounds) {
          if (bounds.maxWidth < MediaQuery.textScalerOf(context).scale(200)) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [name, amountText]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: name), const SizedBox(width: 10), amountText]);
        }),
        if (ref != null)
          Text('Reference ${ref.split('-').first.toUpperCase()}', style: sellerText(metrics, 12, color: SellerUiColors.muted)),
        const SizedBox(height: 8),
        Text(explanation, style: sellerText(metrics, 13, height: 1.4, color: SellerUiColors.body)),
      ]),
    );
  }
}

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
                    InkWell(
                      key: const Key('creditWalletReserved'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _showReservedCredits(context, value),
                      child: Semantics(
                        button: true,
                        label: 'Reserved credits, ${_hc(value.reservedMinor)}. Show details',
                        excludeSemantics: true,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SellerMetricTile(label: 'Reserved', value: _hc(value.reservedMinor)),
                              const SizedBox(width: 2),
                              Icon(Icons.chevron_right_rounded, size: 17,
                                color: HocalistPalette.text(context, SellerUiColors.primaryBright)),
                            ],
                          ),
                        ),
                      ),
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
          _CurrentSellerFees(wallet: value),
          const SizedBox(height: 12),
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

class _CurrentSellerFees extends StatelessWidget {
  const _CurrentSellerFees({required this.wallet});
  final CreditWalletView wallet;

  @override
  Widget build(BuildContext context) {
    final quote = SellerOfferPresentation.fromWallet(wallet, null);
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? _WalletBody._fallbackMetrics(context);
    return SellerStateNotice(
      title: 'Your current targeting fees',
      icon: Icons.sell_outlined,
      body: quote.rateHint ?? 'Add credits to see the rate for your next offer.',
      detail: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (quote.remainingWinningBid != null)
          Wrap(spacing: 24, runSpacing: 8, children: [
            SellerMetricTile(label: 'Initial fee', value: quote.initialBid),
            SellerMetricTile(label: 'Winning total', value: quote.winningBid),
          ]),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: HocalistPalette.text(context, SellerUiColors.primaryBright),
            textStyle: sellerText(metrics, 12, weight: FontWeight.w800).copyWith(
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
            ),
          ),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: const Text('How fees work'),
          onPressed: () => showMoneyHelp(context, title: 'How fees work', seller: true, answers: const {
          'What is reserved?': 'Sending an offer sets credits aside for its fees. Tap Reserved to see each offer and what happens next.',
          'Do I pay both amounts?': 'The winning total includes the initial fee. A PIN-confirmed purchase settles the unpaid part.',
          'Which rate applies?': 'The offer form shows the rate for that request, including any final-hours rate. Existing offers keep their original rate.',
        })),
      ]),
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
        title: 'Compare credit packs',
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
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: HocalistMotion.sheetStyle(context),
      builder: (sheet) => SellerModalSheet(
        icon: Icons.tune_rounded,
        title: 'Filter activity',
        subtitle: 'Show activity',
        onClose: () => Navigator.pop(sheet),
        child: Column(children: [
          for (final choice in ['Recent', 'Reserved', 'Charged'])
            HocalistSheetChoice(
              seller: true, label: choice, selected: filter == choice,
              onTap: () => Navigator.pop(sheet, choice),
            ),
        ]),
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
          Flexible(
            child: Text(
              filter,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'What do these statuses mean?',
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            color: HocalistPalette.text(context, SellerUiColors.primaryBright),
            onPressed: () => showMoneyHelp(
              context,
              seller: true,
              title: 'Activity statuses',
              answers: const {
                'Reserved': 'Credits are set aside for an offer. Tap Reserved on the Credits tab to see which offer is holding them.',
                'Initial fee charged': 'The first targeting fee has been charged. Open the entry to see how much was charged and how much is still held.',
                'Completed': 'The purchase was confirmed and the winning fee was settled. The winning total includes the initial fee.',
                'Released': 'The hold ended. The unused credits are available again.',
                'Refunded': 'A previously charged fee was returned. Open the entry to see the amounts.',
              },
            ),
          ),
          const Spacer(),
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

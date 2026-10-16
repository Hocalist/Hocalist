import '../../components/hocalist_motion.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/phase2/commercial/commercial_wallet_backend.dart';
import '../../data/phase2/marketplace/marketplace_composition.dart';
import '../../data/phase2/marketplace/marketplace_transport.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';

/// Dashboard compatibility read for the approved buyer home reward cards.
///
/// When the commercial reads are configured, this uses the authoritative
/// `commercial_reward_wallet` projection (holds and reversals included) so the
/// home cards and the wallet pane cannot show contradictory balances. It falls
/// back to the reviewed `reward_wallet` RPC until the bundle is applied, and
/// never fabricates a balance.
Future<Map<String, dynamic>> loadBuyerRewards() async {
  final commercial = createConfiguredCommercialWalletBackend();
  if (commercial != null) {
    final view = await commercial.loadRewardWallet();
    return Map<String, dynamic>.from(view.toDashboardMap());
  }
  final adapter = createMarketplaceDataAdapter(
    client: Supabase.instance.client,
  );
  final user = adapter.session.currentUserId;
  if (user == null) throw StateError('signed_out');
  final r = await adapter.transport.callMarketplaceRpc(
    MarketplaceRpcCall(
      schema: 'hocalist',
      function: 'reward_wallet',
      params: {},
    ),
  );
  if (adapter.session.currentUserId != user ||
      r is! MarketplaceTransportData ||
      r.data is! Map) {
    throw StateError('unavailable');
  }
  return Map<String, dynamic>.from(r.data as Map);
}

/// Buyer reward ledger panel.
///
/// The earned, held, pending, processing and available amounts are rendered
/// exactly as `commercial_reward_wallet` reports them. Withdrawal terms and
/// payout availability are shown only when the authoritative policy exists;
/// no rate, minimum or payout capability is assumed locally.
class BuyerRewardsPanel extends StatefulWidget {
  const BuyerRewardsPanel({this.load, super.key});

  final Future<RewardWalletView> Function()? load;

  @override
  State<BuyerRewardsPanel> createState() => _BuyerRewardsPanelState();
}

class _BuyerRewardsPanelState extends State<BuyerRewardsPanel> {
  RewardWalletView? data;
  bool busy = true;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<RewardWalletView> _defaultLoad() async {
    final backend = createConfiguredCommercialWalletBackend();
    if (backend == null) {
      throw const CommercialUnavailableException(
        'Rewards are not available in this build yet.',
      );
    }
    return backend.loadRewardWallet();
  }

  Future<void> refresh() async {
    final run = ++generation;
    setState(() {
      busy = true;
      error = null;
      data = null;
    });
    try {
      final value = await (widget.load ?? _defaultLoad)();
      if (mounted && run == generation) setState(() => data = value);
    } catch (_) {
      if (mounted && run == generation) {
        setState(
          () => error = widget.load == null && !kCommercialReadsEnabled
              ? 'The live rewards ledger has not been enabled yet. Your balance '
                    'will appear here once it is connected.'
              : 'Rewards could not be loaded. Please retry.',
        );
      }
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  static String usd(int cents) =>
      '\$${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  String _statusLabel(RewardItemView item) => switch (item.status) {
    RewardItemStatus.earned =>
      item.holdMinor > 0 ? 'Earned — ${usd(item.holdMinor)} on hold' : 'Earned',
    RewardItemStatus.held => 'On hold until the sale is confirmed',
  };

  BuyerNoticeTone _statusTone(RewardItemView item) => switch (item.status) {
    RewardItemStatus.earned =>
      item.holdMinor > 0 ? BuyerNoticeTone.warning : BuyerNoticeTone.success,
    RewardItemStatus.held => BuyerNoticeTone.neutral,
  };

  String _dateTime(DateTime value) => '${value.toLocal()}'.split('.').first;

  @override
  Widget build(BuildContext context) {
    final value = data;
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Column(
      key: const Key('buyerRewardsPanel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) ...[
          const BuyerProgressStrip(label: 'Updating your rewards…'),
          SizedBox(height: metrics.spacing(10)),
          const BuyerStateNotice(
            icon: Icons.savings_outlined,
            tone: BuyerNoticeTone.brand,
            title: 'Updating your rewards',
            body:
                'Your confirmed rewards and withdrawal status will appear here.',
          ),
        ],
        if (error != null) ...[
          BuyerStateNotice(
            key: const Key('buyerRewardsError'),
            icon: Icons.cloud_off_rounded,
            tone: BuyerNoticeTone.error,
            title: 'Rewards are unavailable',
            body: error!,
            actionKey: const Key('buyerRewardsRetry'),
            actionLabel: 'Retry',
            onAction: busy ? null : refresh,
          ),
        ],
        if (value != null) ...[
          _BalanceCard(value: value),
          SizedBox(height: metrics.spacing(12)),
          if (!value.rewardPolicyConfigured)
            const BuyerStateNotice(
              key: Key('buyerRewardsPolicyUnavailable'),
              icon: Icons.rule_rounded,
              tone: BuyerNoticeTone.warning,
              title: 'Reward rates are not configured yet',
              body:
                  'No reward rate is assumed. Rewards accrue only after a '
                  'confirmed purchase and the related platform fee is collected.',
            )
          else
            BuyerStateNotice(
              key: const Key('buyerRewardsPolicy'),
              icon: Icons.rule_rounded,
              tone: BuyerNoticeTone.brand,
              title: 'Reward rates',
              body:
                  'Normal ${usd(value.normalMinor ?? 0)}'
                  '${value.lateWindowHours == null ? '' : ' · late ${usd(value.lateMinor ?? 0)} within ${value.lateWindowHours}h'}'
                  '. A purchase confirmation alone does not create a reward.',
            ),
          SizedBox(height: metrics.spacing(12)),
          if (!value.withdrawal.configured)
            const BuyerStateNotice(
              key: Key('buyerRewardsWithdrawalUnavailable'),
              icon: Icons.account_balance_outlined,
              tone: BuyerNoticeTone.warning,
              title: 'Withdrawals are not configured yet',
              body:
                  'No payout request or destination will be collected until '
                  'the withdrawal policy is published.',
            )
          else ...[
            BuyerStateNotice(
              key: const Key('buyerRewardsWithdrawalTerms'),
              icon: Icons.account_balance_outlined,
              tone: BuyerNoticeTone.brand,
              title: 'Withdrawal terms',
              body:
                  'Minimum ${usd(value.withdrawal.minimumMinor ?? 0)} · '
                  'fee ${usd(value.withdrawal.feeMinor ?? 0)}. '
                  'Email verified: ${value.withdrawal.emailVerified ? 'yes' : 'no'} · '
                  'phone verified: ${value.withdrawal.phoneVerified ? 'yes' : 'no'}.',
            ),
            SizedBox(height: metrics.spacing(8)),
            if (!value.payout.providerConfigured ||
                !value.payout.executionEnabled)
              const BuyerStateNotice(
                key: Key('buyerRewardsPayoutUnavailable'),
                icon: Icons.hourglass_empty_rounded,
                tone: BuyerNoticeTone.warning,
                title: 'Withdrawals are not available yet',
                body:
                    'Payout execution is provider-neutral and stays off '
                    'until the payout provider is verified. Nothing is '
                    'simulated and no bank details are collected here.',
              ),
          ],
          SizedBox(height: metrics.spacing(16)),
          const BuyerSectionHeading(title: 'Recent rewards'),
          if (value.items.isEmpty)
            const BuyerStateNotice(
              icon: Icons.savings_outlined,
              tone: BuyerNoticeTone.neutral,
              title: 'No earned rewards yet.',
              body:
                  'Rewards from eligible confirmed purchases will appear here. '
                  'You can check each reward and its status in this section.',
            )
          else
            for (final item in value.items)
              Padding(
                padding: EdgeInsets.only(bottom: metrics.spacing(8)),
                child: _RewardRow(
                  item: item,
                  statusLabel: _statusLabel(item),
                  statusTone: _statusTone(item),
                  createdAt: _dateTime(item.createdAt),
                ),
              ),
          if (value.reversalPolicy.rewardHoldConfigured ||
              value.reversalPolicy.clawbackModeConfigured)
            Padding(
              padding: EdgeInsets.only(top: metrics.spacing(4)),
              child: Text(
                'A reviewed dispute can hold the related reward; holds never '
                'touch unrelated funds.',
                style: BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.secondaryBody,
                ),
              ),
            ),
        ],
        SizedBox(height: metrics.spacing(10)),
        BuyerSecondaryButton(
          key: const Key('buyerRewardsRefresh'),
          label: 'Refresh rewards',
          onPressed: busy ? null : refresh,
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.value});

  final RewardWalletView value;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return HocalistEntrance(
      child: Container(
        padding: metrics.geometryInsets(const EdgeInsets.all(18)),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xfff4f2ff), Color(0xffeeedff)],
          ),
          borderRadius: BorderRadius.circular(metrics.geometry(18)),
          border: Border.all(color: const Color(0xffd9d5ff)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: metrics.artSize(34),
                  height: metrics.artSize(34),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: BuyerGlyphIcon(
                      icon: Icons.savings_rounded,
                      slotSize: metrics.artSize(19),
                      glyphSize: metrics.artSize(19),
                      color: BuyerUiTokens.action,
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
              _BuyerRewardsPanelState.usd(value.availableMinor),
              key: const Key('buyerRewardsAvailable'),
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
                  value: _BuyerRewardsPanelState.usd(value.earnedMinor),
                  valueKey: const Key('buyerRewardsEarned'),
                ),
                BuyerMetricTile(
                  label: 'Held',
                  value: _BuyerRewardsPanelState.usd(value.heldMinor),
                  valueKey: const Key('buyerRewardsHeld'),
                  tone: value.heldMinor > 0
                      ? BuyerNoticeTone.warning
                      : BuyerNoticeTone.neutral,
                ),
                BuyerMetricTile(
                  label: 'Processing',
                  value: _BuyerRewardsPanelState.usd(value.processingMinor),
                  valueKey: const Key('buyerRewardsProcessing'),
                ),
                BuyerMetricTile(
                  label: 'Paid out',
                  value: _BuyerRewardsPanelState.usd(value.paidMinor),
                  valueKey: const Key('buyerRewardsPaid'),
                  tone: BuyerNoticeTone.success,
                ),
              ],
            ),
            if (value.shortfallMinor > 0) ...[
              SizedBox(height: metrics.spacing(12)),
              Container(
                padding: metrics.geometryInsets(const EdgeInsets.all(10)),
                decoration: BoxDecoration(
                  color: const Color(0xfffff6e5),
                  borderRadius: BorderRadius.circular(metrics.geometry(12)),
                  border: Border.all(color: const Color(0xffffe0a3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: metrics.artSize(18),
                      color: const Color(0xffb56200),
                    ),
                    SizedBox(width: metrics.spacing(8)),
                    Expanded(
                      child: Text(
                        'Reversed but not recovered: '
                        '${_BuyerRewardsPanelState.usd(value.shortfallMinor)}. '
                        'Recorded for review; it is not deducted from your other '
                        'rewards.',
                        key: const Key('buyerRewardsShortfall'),
                        style: BuyerTypography.style(
                          context,
                          metrics,
                          BuyerTextRole.secondaryBody,
                          color: BuyerUiTokens.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.item,
    required this.statusLabel,
    required this.statusTone,
    required this.createdAt,
  });

  final RewardItemView item;
  final String statusLabel;
  final BuyerNoticeTone statusTone;
  final String createdAt;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Container(
      padding: metrics.geometryInsets(const EdgeInsets.all(14)),
      decoration: BoxDecoration(
        color: BuyerUiTokens.surface,
        borderRadius: BorderRadius.circular(metrics.geometry(14)),
        border: Border.all(color: BuyerUiTokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: metrics.artSize(32),
            height: metrics.artSize(32),
            decoration: const BoxDecoration(
              color: BuyerUiTokens.softSurface,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: BuyerGlyphIcon(
                icon: Icons.redeem_rounded,
                slotSize: metrics.artSize(17),
                glyphSize: metrics.artSize(17),
                color: BuyerUiTokens.action,
              ),
            ),
          ),
          SizedBox(width: metrics.spacing(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemTitle ?? 'Confirmed purchase',
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.cardTitle,
                  ).copyWith(fontSize: metrics.fontSize(13)),
                ),
                SizedBox(height: metrics.spacing(4)),
                Wrap(
                  spacing: metrics.spacing(8),
                  runSpacing: metrics.spacing(4),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    BuyerStatusChip(
                      label: statusLabel,
                      key: Key('reward-${item.id}'),
                      tone: statusTone,
                      icon: statusTone == BuyerNoticeTone.success
                          ? Icons.check_circle_rounded
                          : statusTone == BuyerNoticeTone.warning
                          ? Icons.schedule_rounded
                          : Icons.hourglass_empty_rounded,
                    ),
                    Text(
                      createdAt,
                      style: BuyerTypography.style(
                        context,
                        metrics,
                        BuyerTextRole.metadata,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: metrics.spacing(8)),
          Text(
            _BuyerRewardsPanelState.usd(item.amountMinor),
            style: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.cardTitle,
              color: BuyerUiTokens.success,
            ).copyWith(fontSize: metrics.fontSize(14)),
          ),
        ],
      ),
    );
  }
}

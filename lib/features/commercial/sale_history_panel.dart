import 'package:flutter/material.dart';
import '../../components/hocalist_motion.dart';

import '../../data/phase2/commercial/commercial_wallet_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';

/// Role-aware completed-purchase/sale history with an authoritative drill-down.
///
/// The list and detail are server reads (`commercial_sale_history` and
/// `commercial_sale_detail`); item payment is shown as offline and platform
/// fees/rewards come from the ledger, never from local arithmetic.
class SaleHistoryPanel extends StatefulWidget {
  const SaleHistoryPanel({this.load, this.loadDetail, super.key});

  final Future<List<SaleHistoryEntryView>> Function({
    DateTime? beforeTime,
    String? beforeId,
  })?
  load;
  final Future<SaleDetailView> Function(String outcomeId)? loadDetail;

  @override
  State<SaleHistoryPanel> createState() => _SaleHistoryPanelState();
}

String _usd(int cents) =>
    '\$${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

class _SaleHistoryPanelState extends State<SaleHistoryPanel> {
  final items = <SaleHistoryEntryView>[];
  bool busy = false;
  bool more = true;
  String? error;
  int generation = 0;
  String? expandedId;
  SaleDetailView? detail;
  bool detailBusy = false;
  String? detailError;

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

  Future<List<SaleHistoryEntryView>> _defaultLoad({
    DateTime? beforeTime,
    String? beforeId,
  }) async {
    final backend = createConfiguredCommercialWalletBackend();
    if (backend == null) {
      throw const CommercialUnavailableException(
        'Sale history is not available in this build yet.',
      );
    }
    return backend.loadSaleHistory(beforeTime: beforeTime, beforeId: beforeId);
  }

  Future<SaleDetailView> _defaultDetail(String id) async {
    final backend = createConfiguredCommercialWalletBackend();
    if (backend == null) {
      throw const CommercialUnavailableException(
        'Sale details are not available in this build yet.',
      );
    }
    return backend.loadSaleDetail(id);
  }

  Future<void> load({bool refresh = false}) async {
    if (busy) return;
    final run = ++generation;
    setState(() {
      busy = true;
      error = null;
      if (refresh) {
        items.clear();
        more = true;
        expandedId = null;
        detail = null;
      }
    });
    try {
      final rows = await (widget.load ?? _defaultLoad)(
        beforeTime: items.isEmpty ? null : items.last.confirmedAt,
        beforeId: items.isEmpty ? null : items.last.id,
      );
      if (!mounted || run != generation) return;
      setState(() {
        for (final row in rows) {
          if (!items.any((old) => old.id == row.id)) items.add(row);
        }
        more = rows.length == 25;
      });
    } catch (_) {
      if (mounted && run == generation) {
        setState(
          () =>
              error = 'Completed purchases could not be loaded. Please retry.',
        );
      }
    } finally {
      if (mounted && run == generation) setState(() => busy = false);
    }
  }

  Future<void> toggleDetail(SaleHistoryEntryView entry) async {
    if (expandedId == entry.id) {
      setState(() {
        expandedId = null;
        detail = null;
        detailError = null;
      });
      return;
    }
    setState(() {
      expandedId = entry.id;
      detail = null;
      detailError = null;
      detailBusy = true;
    });
    await _loadDetail(entry);
  }

  Future<void> retryDetail(SaleHistoryEntryView entry) async {
    if (expandedId != entry.id) return;
    setState(() {
      detail = null;
      detailError = null;
      detailBusy = true;
    });
    await _loadDetail(entry);
  }

  Future<void> _loadDetail(SaleHistoryEntryView entry) async {
    try {
      final value = await (widget.loadDetail ?? _defaultDetail)(entry.id);
      if (!mounted || expandedId != entry.id) return;
      setState(() {
        detail = value;
        detailBusy = false;
      });
    } catch (_) {
      if (!mounted || expandedId != entry.id) return;
      setState(() {
        detailBusy = false;
        detailError = 'Sale details could not be loaded. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Column(
      key: const Key('saleHistoryPanel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) ...[
          const BuyerProgressStrip(label: 'Loading your history…'),
          SizedBox(height: metrics.spacing(10)),
        ],
        if (error != null) ...[
          BuyerStateNotice(
            key: const Key('saleHistoryError'),
            icon: Icons.cloud_off_rounded,
            tone: BuyerNoticeTone.error,
            title: 'Purchase history unavailable',
            body: error!,
            actionKey: const Key('saleHistoryRetry'),
            actionLabel: 'Retry',
            onAction: busy ? null : load,
          ),
          SizedBox(height: metrics.spacing(10)),
        ],
        if (!busy && error == null && items.isEmpty)
          const BuyerStateNotice(
            icon: Icons.receipt_long_outlined,
            tone: BuyerNoticeTone.neutral,
            title: 'No confirmed purchases yet',
            body: 'Your ongoing meetings remain in Meetings.',
          ),
        for (final item in items) ...[
          _EntryCard(
            entry: item,
            expanded: expandedId == item.id,
            detailBusy: detailBusy && expandedId == item.id,
            detailError: expandedId == item.id ? detailError : null,
            detail: expandedId == item.id ? detail : null,
            onTap: () => toggleDetail(item),
            onRetryDetail: () => retryDetail(item),
          ),
          SizedBox(height: metrics.spacing(10)),
        ],
        Text(
          'Item payment takes place outside Hocalist. Rewards are recorded '
          'separately after the platform fee is collected.',
          style: BuyerTypography.style(
            context,
            metrics,
            BuyerTextRole.secondaryBody,
          ),
        ),
        SizedBox(height: metrics.spacing(10)),
        if (more && items.isNotEmpty) ...[
          BuyerSecondaryButton(
            key: const Key('saleHistoryLoadMore'),
            label: 'Load more',
            onPressed: busy ? null : load,
          ),
          SizedBox(height: metrics.spacing(8)),
        ],
        BuyerSecondaryButton(
          key: const Key('saleHistoryRefresh'),
          label: 'Refresh history',
          onPressed: busy ? null : () => load(refresh: true),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.expanded,
    required this.detailBusy,
    required this.detailError,
    required this.detail,
    required this.onTap,
    required this.onRetryDetail,
  });

  final SaleHistoryEntryView entry;
  final bool expanded;
  final bool detailBusy;
  final String? detailError;
  final SaleDetailView? detail;
  final VoidCallback onTap;
  final VoidCallback onRetryDetail;

  static String _money(String currency, int minor) {
    final symbol = currency == 'USD' ? '\$' : '$currency ';
    return '$symbol${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
  }

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
        decoration: BoxDecoration(
          color: BuyerUiTokens.surface,
          borderRadius: BorderRadius.circular(metrics.geometry(14)),
          border: Border.all(
            color: expanded ? const Color(0xffd9d5ff) : BuyerUiTokens.border,
            width: expanded ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(metrics.geometry(14)),
              child: InkWell(
                key: Key('saleHistoryEntry-${entry.id}'),
                onTap: onTap,
                borderRadius: BorderRadius.circular(metrics.geometry(14)),
                child: Padding(
                  padding: metrics.geometryInsets(const EdgeInsets.all(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                                icon: entry.side == SaleSide.purchase
                                    ? Icons.shopping_bag_outlined
                                    : Icons.storefront_outlined,
                                slotSize: metrics.artSize(17),
                                glyphSize: metrics.artSize(17),
                                color: BuyerUiTokens.action,
                              ),
                            ),
                          ),
                          SizedBox(width: metrics.spacing(10)),
                          Expanded(
                            child: Text(
                              entry.title,
                              style: BuyerTypography.style(
                                context,
                                metrics,
                                BuyerTextRole.cardTitle,
                              ).copyWith(fontSize: metrics.fontSize(14)),
                            ),
                          ),
                          SizedBox(width: metrics.spacing(8)),
                          Flexible(
                            child: BuyerStatusChip(
                              label: expanded ? 'Hide' : 'Details',
                              tone: expanded
                                  ? BuyerNoticeTone.brand
                                  : BuyerNoticeTone.neutral,
                              icon: expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: metrics.spacing(8)),
                      Wrap(
                        spacing: metrics.spacing(8),
                        runSpacing: metrics.spacing(5),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          BuyerStatusChip(
                            label: entry.side == SaleSide.purchase
                                ? 'Purchase'
                                : 'Sale',
                            icon: entry.side == SaleSide.purchase
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            tone: entry.side == SaleSide.purchase
                                ? BuyerNoticeTone.brand
                                : BuyerNoticeTone.success,
                          ),
                          Text(
                            _money(entry.currency, entry.priceMinor),
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.cardTitle,
                              color: BuyerUiTokens.text,
                            ).copyWith(fontSize: metrics.fontSize(12.5)),
                          ),
                          Text(
                            'Confirmed ${entry.confirmedAt.toLocal()}'
                                .split('.')
                                .first,
                            style: BuyerTypography.style(
                              context,
                              metrics,
                              BuyerTextRole.metadata,
                            ),
                          ),
                        ],
                      ),
                      if (entry.reward != null) ...[
                        SizedBox(height: metrics.spacing(6)),
                        BuyerStatusChip(
                          key: Key('saleHistoryReward-${entry.id}'),
                          label:
                              'Reward ${entry.reward!.status}'
                              '${entry.reward!.amountMinor > 0 ? ' · ${_usd(entry.reward!.amountMinor)}' : ''}',
                          tone: BuyerNoticeTone.warning,
                          icon: Icons.redeem_rounded,
                        ),
                      ],
                      if (entry.fee != null) ...[
                        SizedBox(height: metrics.spacing(6)),
                        BuyerStatusChip(
                          key: Key('saleHistoryFee-${entry.id}'),
                          label:
                              'Fee ${entry.fee!.status} · charged '
                              '${_money(entry.currency, entry.fee!.chargedMinor)}'
                              '${entry.fee!.rateVersion == null ? '' : ' · rate ${entry.fee!.rateVersion}'}',
                          tone: BuyerNoticeTone.neutral,
                          icon: Icons.receipt_outlined,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            HocalistExpand(
              child: expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1, color: BuyerUiTokens.border),
                        Padding(
                          padding: metrics.geometryInsets(
                            const EdgeInsets.all(14),
                          ),
                          child: detailBusy
                              ? const BuyerProgressStrip(
                                  label: 'Loading sale details…',
                                )
                              : detailError != null
                              ? BuyerStateNotice(
                                  key: Key('saleDetailError-${entry.id}'),
                                  icon: Icons.error_outline_rounded,
                                  tone: BuyerNoticeTone.error,
                                  title: 'Sale details unavailable',
                                  body: detailError,
                                  actionLabel: 'Retry details',
                                  onAction: onRetryDetail,
                                )
                              : detail == null
                              ? const SizedBox.shrink()
                              : _DetailBody(detail: detail!),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final SaleDetailView detail;

  @override
  Widget build(BuildContext context) {
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Column(
      key: Key('saleDetail-${detail.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.description.isNotEmpty) ...[
          Text(
            detail.description,
            style: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.primaryBody,
            ),
          ),
          SizedBox(height: metrics.spacing(8)),
        ],
        Wrap(
          spacing: metrics.spacing(18),
          runSpacing: metrics.spacing(10),
          children: [
            BuyerMetricTile(
              label: 'Schedule date',
              value: '${detail.schedule.date}'.split(' ').first,
            ),
            BuyerMetricTile(
              label: 'Schedule time',
              value: detail.schedule.time,
            ),
            BuyerMetricTile(label: 'Zone', value: detail.schedule.timezone),
            if (detail.schedule.placeLabel != null)
              BuyerMetricTile(
                label: 'Place',
                value: detail.schedule.placeLabel!,
              ),
            if (detail.schedule.meetingExpiresAt != null)
              BuyerMetricTile(
                label: 'Meeting window ends',
                value: '${detail.schedule.meetingExpiresAt!.toLocal()}'
                    .split('.')
                    .first,
              ),
          ],
        ),
        SizedBox(height: metrics.spacing(10)),
        Container(
          padding: metrics.geometryInsets(const EdgeInsets.all(10)),
          decoration: BoxDecoration(
            color: BuyerUiTokens.softSurface,
            borderRadius: BorderRadius.circular(metrics.geometry(11)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BuyerGlyphIcon(
                icon: Icons.handshake_outlined,
                slotSize: metrics.artSize(17),
                glyphSize: metrics.artSize(17),
                color: BuyerUiTokens.action,
              ),
              SizedBox(width: metrics.spacing(8)),
              Expanded(
                child: Text(
                  'Item payment happens offline. Hocalist does not process it.',
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.secondaryBody,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

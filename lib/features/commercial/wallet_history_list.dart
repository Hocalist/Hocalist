import 'package:flutter/material.dart';
import '../../components/hocalist_motion.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/seller_ui_foundation.dart';

class WalletHistoryEntry {
  const WalletHistoryEntry({
    required this.id,
    required this.title,
    required this.date,
    required this.amount,
    required this.status,
    required this.facts,
    this.note,
  });
  final String id, title, amount, status;
  final DateTime date;
  final Map<String, String> facts;
  final String? note;
}

/// Pages the authoritative wallet read; changing a filter creates its own list.
class WalletHistoryList extends StatefulWidget {
  const WalletHistoryList({
    required this.entries,
    required this.kind,
    super.key,
  });
  final List<WalletHistoryEntry> entries;
  final String kind;
  @override
  State<WalletHistoryList> createState() => _WalletHistoryListState();
}

class _WalletHistoryListState extends State<WalletHistoryList> {
  Color statusColor(String status) => switch (status) {
    'Completed' => const Color(0xFF16834A),
    'Initial fee charged' => const Color(0xFFB36A00),
    'Reserved' => const Color(0xFF3155B7),
    'Refunded' || 'Released' => const Color(0xFF7952B3),
    _ => SellerUiColors.primaryBright,
  };
  IconData statusIcon(String status) => switch (status) {
    'Completed' => Icons.check_circle_outline,
    'Initial fee charged' => Icons.receipt_long_outlined,
    'Reserved' => Icons.lock_outline,
    'Refunded' || 'Released' => Icons.undo,
    _ => Icons.account_balance_wallet_outlined,
  };
  static const pageSize = 5;
  int page = 0;
  @override
  void didUpdateWidget(WalletHistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.map((e) => e.id).join('|') !=
        widget.entries.map((e) => e.id).join('|')) {
      page = 0;
    }
  }

  Future<void> details(WalletHistoryEntry entry) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: HocalistPalette.surface(context, Colors.white),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    sheetAnimationStyle: HocalistMotion.sheetStyle(context),
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SellerUiColors.lavenderBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close details',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                entry.status,
                style: const TextStyle(
                  color: SellerUiColors.primaryBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                MaterialLocalizations.of(
                  context,
                ).formatFullDate(entry.date.toLocal()),
              ),
              const SizedBox(height: 16),
              for (final fact in entry.facts.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          fact.key,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Text(
                          fact.value,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (entry.note != null) ...[
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  entry.note!,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 16),
              ],
              SellerPrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pages = (widget.entries.length / pageSize).ceil().clamp(1, 1000000);
    final current = page.clamp(0, pages - 1);
    final sorted = [...widget.entries]
      ..sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date != 0 ? date : b.id.compareTo(a.id);
      });
    final visible = sorted.skip(current * pageSize).take(pageSize);
    return Container(
      key: ValueKey('walletHistory-${widget.kind}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible) ...[
            Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                key: ValueKey('${widget.kind}-${entry.id}'),
                onTap: () => details(entry),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: statusColor(entry.status).withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(statusIcon(entry.status), size: 20,
                          color: statusColor(entry.status)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              MaterialLocalizations.of(
                                context,
                              ).formatShortDate(entry.date.toLocal()),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              entry.amount,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              entry.status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusColor(entry.status),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: SellerUiColors.primaryBright,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, indent: 14, endIndent: 14),
          ],
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: current == 0
                      ? null
                      : () => setState(() => page = current - 1),
                  child: const Text('Previous'),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Page ${current + 1} of $pages',
                    key: ValueKey('walletPage-${widget.kind}'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: current + 1 >= pages
                      ? null
                      : () => setState(() => page = current + 1),
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

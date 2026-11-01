import 'package:flutter/material.dart';
import '../../domain/phase2/customers.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../theme/adaptive_palette.dart';
import '../../components/hocalist_motion.dart';
import '../../components/hocalist_paged_list.dart';
import '../../data/local_marketplace_repository.dart';

class SellerCustomersPage extends StatefulWidget {
  const SellerCustomersPage({super.key, required this.load, required this.save,
    required this.history, required this.onBack, this.onUpgrade});
  final VoidCallback? onUpgrade;
  final Future<SellerCustomerList> Function() load;
  final Future<void> Function(String, bool, String) save;
  final Future<CustomerHistory> Function(String) history;
  final VoidCallback onBack;
  @override
  State<SellerCustomersPage> createState() => _SellerCustomersPageState();
}

class _SellerCustomersPageState extends State<SellerCustomersPage> {
  SellerCustomerList? data;
  bool busy = true;
  String? error;
  bool upgradeRequired = false;
  final drafts = <String, _CustomerDraft>{};
  @override
  void dispose() {
    for (final draft in drafts.values) { draft.dispose(); }
    super.dispose();
  }
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() { busy = true; error = null; upgradeRequired = false; });
    try {
      final result = await widget.load();
      if (mounted) setState(() => data = result);
    } catch (failure) {
      if (mounted) setState(() {
        upgradeRequired = failure is StoreBackendException && failure.code == 'contacts_plan_required';
        error = 'Customers could not be loaded. Please try again.';
      });
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => SellerResponsivePage(
    builder: (context, metrics) => ListView(
      padding: EdgeInsets.all(metrics.pageHorizontalPadding(16)),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: metrics.artSize(44), height: metrics.artSize(44),
            child: IconButton(tooltip: 'Back', onPressed: widget.onBack,
              icon: Icon(Icons.arrow_back, size: metrics.artSize(23)))),
          Expanded(child: Column(children: [
            Text('Customers', style: sellerText(metrics, 16, weight: FontWeight.w800)),
            SizedBox(height: metrics.spacing(3)),
            Text('Keep your confirmed buyers close.', textAlign: TextAlign.center,
              style: sellerText(metrics, 12, color: SellerUiColors.muted)),
          ])),
          SizedBox(width: metrics.artSize(44)),
        ]),
        SizedBox(height: metrics.spacing(18)),
        Padding(padding: EdgeInsets.only(left: metrics.spacing(2), bottom: metrics.spacing(7)),
          child: Text('CONFIRMED CUSTOMERS', style: sellerText(metrics, 11,
            weight: FontWeight.w800, color: SellerUiColors.muted, letterSpacing: .8))),
        if (busy) const SellerProgressStrip(label: 'Loading customers…'),
        if (upgradeRequired)
          Container(
            key: const Key('customersUpgradeCard'),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: HocalistPalette.surface(context, SellerUiColors.lavender),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HocalistPalette.border(context, SellerUiColors.lavenderBorder)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.workspace_premium_outlined, size: 32,
                color: HocalistPalette.text(context, SellerUiColors.primaryBright)),
              const SizedBox(height: 12),
              Text('Unlock your customer list', style: sellerText(metrics, 19, weight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Available with Pro and Elite', style: sellerText(metrics, 13, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Keep your confirmed buyers together, save customers and add private notes.',
                style: sellerText(metrics, 13, color: SellerUiColors.body, height: 1.5)),
              const SizedBox(height: 20),
              SellerPrimaryButton(key: const Key('customersUpgradePlan'), label: 'Upgrade plan', onPressed: widget.onUpgrade),
            ]),
          )
        else if (error != null)
          SellerStateNotice(icon: Icons.cloud_off_outlined, title: 'Customers unavailable',
            body: error, actionLabel: 'Retry', onAction: refresh),
        if (!busy && error == null && data!.items.isEmpty)
          const Text('No confirmed customers yet. Buyers appear here after a purchase is confirmed.'),
        if (!busy && error == null)
          if (data!.items.isNotEmpty)
            HocalistPagedList<SellerCustomer>(
              items: data!.items, pageSize: 10,
              itemBuilder: (context, customer) => _CustomerCard(
                key: ValueKey(customer.buyerId), customer: customer,
                draft: drafts.putIfAbsent(customer.buyerId, () => _CustomerDraft(customer)),
                insights: data!.insightsAvailable, save: widget.save, history: widget.history),
            ),
      ],
    ),
  );
}

class _CustomerCard extends StatefulWidget {
  const _CustomerCard({super.key, required this.customer, required this.insights,
    required this.save, required this.history, required this.draft});
  final _CustomerDraft draft;
  final SellerCustomer customer;
  final bool insights;
  final Future<void> Function(String, bool, String) save;
  final Future<CustomerHistory> Function(String) history;
  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerDraft extends ChangeNotifier {
  _CustomerDraft(SellerCustomer customer)
      : note = TextEditingController(text: customer.note), saved = customer.saved;
  final TextEditingController note;
  bool saved;
  bool busy = false;
  bool loadingHistory = false;
  bool notesExpanded = false;
  ({bool saved, String note})? pending;
  String? error;
  String? historyError;
  CustomerHistory? facts;
  bool disposed = false;
  void update(VoidCallback change) {
    if (disposed) return;
    change();
    notifyListeners();
  }
  @override
  void dispose() { disposed = true; note.dispose(); super.dispose(); }
}

class _CustomerCardState extends State<_CustomerCard> {
  _CustomerDraft get draft => widget.draft;
  void changed() { if (mounted) setState(() {}); }
  @override
  void initState() {
    super.initState(); draft.addListener(changed);
  }
  @override
  void dispose() { draft.removeListener(changed); super.dispose(); }
  Future<void> submit() async {
    if (draft.busy) return;
    draft.pending ??= (saved: draft.saved, note: draft.note.text);
    final intent = draft.pending!;
    draft.update(() { draft.busy = true; draft.error = null; });
    try {
      await widget.save(widget.customer.buyerId, intent.saved, intent.note);
      draft.update(() { draft.pending = null; draft.error = 'Customer preferences saved.'; });
    } catch (_) {
      draft.update(() => draft.error = 'Save was not confirmed. Retry to confirm the same changes.');
    } finally { draft.update(() => draft.busy = false); }
  }
  Future<void> loadHistory() async {
    if (draft.loadingHistory) return;
    draft.update(() { draft.loadingHistory = true; draft.historyError = null; });
    try {
      final result = await widget.history(widget.customer.buyerId);
      draft.update(() => draft.facts = result);
    } catch (_) {
      draft.update(() => draft.historyError = 'Purchase history could not be loaded. Retry.');
    } finally { draft.update(() => draft.loadingHistory = false); }
  }
  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final outline = OutlineInputBorder(borderRadius: BorderRadius.circular(metrics.geometry(12)),
      borderSide: BorderSide(color: HocalistPalette.border(context, SellerUiColors.lavenderBorder)));
    return HocalistEntrance(child: Container(
      margin: EdgeInsets.only(bottom: metrics.spacing(12)),
      decoration: BoxDecoration(color: HocalistPalette.surface(context, SellerUiColors.white),
        border: Border.all(color: HocalistPalette.border(context, SellerUiColors.line)),
        borderRadius: BorderRadius.circular(metrics.geometry(14))),
      padding: EdgeInsets.all(metrics.spacing(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: metrics.artSize(44), height: metrics.artSize(44),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: HocalistPalette.surface(context, SellerUiColors.lavender),
            borderRadius: BorderRadius.circular(metrics.geometry(13))),
          child: Icon(Icons.person_outline_rounded, color: HocalistPalette.text(context, SellerUiColors.primaryBright), size: metrics.artSize(24))),
        SizedBox(width: metrics.spacing(11)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.customer.displayName, style: sellerText(metrics, 14, weight: FontWeight.w800)),
          SizedBox(height: metrics.spacing(3)),
          Text('${widget.customer.purchaseCount} confirmed purchases with you',
            style: sellerText(metrics, 11, color: SellerUiColors.muted)),
        ])),
        IconButton(key: const Key('customer-save-toggle'),
          tooltip: draft.saved ? 'Remove saved customer' : 'Save customer',
          onPressed: draft.busy || draft.pending != null ? null : () {
            draft.update(() => draft.saved = !draft.saved); submit();
          },
          icon: Icon(draft.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: HocalistPalette.text(context, SellerUiColors.primaryBright), size: metrics.artSize(23))),
      ]),
      SizedBox(height: metrics.spacing(12)),
      Divider(height: 1, color: HocalistPalette.border(context, SellerUiColors.line)),
      SizedBox(height: metrics.spacing(12)),
      TextButton(onPressed: () => draft.update(() => draft.notesExpanded = !draft.notesExpanded),
        child: Row(children: [
          Icon(Icons.edit_note_rounded, size: metrics.artSize(20), color: HocalistPalette.text(context, SellerUiColors.primaryBright)),
          SizedBox(width: metrics.spacing(8)),
          Expanded(child: Text('Private notes', style: sellerText(metrics, 12, weight: FontWeight.w700))),
          Icon(draft.notesExpanded ? Icons.expand_less : Icons.chevron_right, size: metrics.artSize(20), color: HocalistPalette.text(context, SellerUiColors.primaryBright)),
        ])),
      if (draft.notesExpanded) ...[
        Text('Only you can see these notes.', style: sellerText(metrics, 11, color: SellerUiColors.muted)),
        SizedBox(height: metrics.spacing(8)),
        TextField(controller: draft.note, enabled: !draft.busy && draft.pending == null, maxLength: 2000,
          style: sellerText(metrics, 12), minLines: 2, maxLines: 4,
          decoration: InputDecoration(hintText: 'Add a note about this customer',
            hintStyle: sellerText(metrics, 12, color: SellerUiColors.muted),
            filled: true, fillColor: HocalistPalette.surface(context, SellerUiColors.lavender),
            contentPadding: EdgeInsets.all(metrics.spacing(12)), border: outline,
            enabledBorder: outline, focusedBorder: outline.copyWith(borderSide: const BorderSide(color: SellerUiColors.primaryBright, width: 1.5)))),
        SellerPrimaryButton(label: draft.busy ? 'Saving…' : draft.pending == null ? 'Save notes' : 'Retry save',
          onPressed: draft.busy ? null : submit),
      ] else if (draft.pending != null && !draft.busy)
        SellerSecondaryButton(label: 'Retry save', onPressed: submit),
      if (draft.error != null) Padding(padding: EdgeInsets.only(top: metrics.spacing(7)),
        child: Text(draft.error!, style: sellerText(metrics, 11, color: SellerUiColors.muted))),
      if (widget.insights) ...[
        TextButton(onPressed: draft.loadingHistory ? null : draft.facts == null
            ? loadHistory : () => draft.update(() => draft.facts = null),
          child: Text(draft.loadingHistory ? 'Loading history…'
              : draft.facts == null ? 'View purchase history' : 'Close purchase history',
            style: sellerText(metrics, 12, weight: FontWeight.w700, color: SellerUiColors.primaryBright))),
        if (draft.historyError != null) Text(draft.historyError!, style: sellerText(metrics, 11)),
        if (draft.facts case final history?) ...[
          Container(padding: EdgeInsets.all(metrics.spacing(12)),
            decoration: BoxDecoration(color: HocalistPalette.surface(context, SellerUiColors.lavender),
              borderRadius: BorderRadius.circular(metrics.geometry(11))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(history.completionPercent == null ? 'Completion rate unavailable: no concluded requests.'
                : 'Historical completion rate: ${history.completionPercent!.toStringAsFixed(1)}%',
                style: sellerText(metrics, 13, weight: FontWeight.w800)),
              SizedBox(height: metrics.spacing(6)),
              Text('${history.confirmedPurchases} of ${history.concludedRequests} concluded requests had a confirmed purchase', style: sellerText(metrics, 11)),
              SizedBox(height: metrics.spacing(6)),
              Text('${history.ongoingRequests} ongoing requests excluded. This is recorded history, not a prediction of a future purchase.',
                style: sellerText(metrics, 11, color: SellerUiColors.muted)),
            ])),
        ],
      ] else Padding(padding: EdgeInsets.only(top: metrics.spacing(12)),
        child: Text('Purchase history insights require Elite.', style: sellerText(metrics, 11, color: SellerUiColors.muted))),
    ]),
  ));
  }
}

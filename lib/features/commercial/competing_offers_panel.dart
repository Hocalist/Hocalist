import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/phase2/commercial/entitlement_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/seller_ui_foundation.dart';

/// Prices are loaded only after explicit consent. The server owns eligibility.
class CompetingOffersPanel extends StatefulWidget {
  const CompetingOffersPanel({
    required this.requestId,
    this.loadElite,
    this.loadPrices,
    super.key,
  });
  final String requestId;
  final Future<bool> Function()? loadElite;
  final Future<List<String>> Function(String)? loadPrices;
  @override
  State<CompetingOffersPanel> createState() => _CompetingOffersPanelState();
}

class _CompetingOffersPanelState extends State<CompetingOffersPanel> {
  bool _elite = false, _confirm = false, _busy = false;
  List<String>? _prices;
  String? _error;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final elite = await (widget.loadElite?.call() ?? _isElite());
      if (mounted) setState(() => _elite = elite);
    } catch (_) {
      /* Fail closed when entitlement is unavailable. */
    }
  }

  Future<bool> _isElite() async =>
      (await createConfiguredEntitlementBackend()?.loadEntitlement())
          ?.effectivePlan ==
      PlanCode.elite;
  Future<List<String>> _load(String request) async {
    final client = Supabase.instance.client;
    final identity = client.auth.currentUser?.id;
    if (identity == null) throw StateError('signed out');
    final data = await client
        .schema('hocalist')
        .rpc('credit_view_competing_offers', params: {'p_request': request});
    if (identity != client.auth.currentUser?.id)
      throw StateError('session changed');
    if (data is! Map ||
        data['refund_eligible'] != false ||
        data['offers'] is! List) {
      throw const FormatException('Invalid prices');
    }
    return (data['offers'] as List)
        .map((row) {
          if (row is! Map ||
              row['price_minor'] is! int ||
              row['currency_code'] is! String ||
              (row['price_minor'] as int) < 0)
            throw const FormatException('Invalid price');
          return '${row['currency_code']} ${((row['price_minor'] as int) / 100).toStringAsFixed(2)}';
        })
        .toList(growable: false);
  }

  Future<void> _view() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final prices = await (widget.loadPrices ?? _load)(widget.requestId);
      if (mounted)
        setState(() {
          _prices = prices;
          _confirm = false;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Competing offers are unavailable for this deal. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_elite) return const SizedBox.shrink();
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness,
      availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final body = sellerText(metrics, 12, color: SellerUiColors.body, height: 1.45);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: Alignment.centerLeft,
            child: SellerPlanBadge(label: 'Elite benefit')),
          const SizedBox(height: 8),
          if (_prices != null) ...[
            const SellerSectionHeading(title: 'Competing offer prices'),
            const SizedBox(height: 8),
            Text(
              _prices!.isEmpty
                  ? 'No competing offers are available.'
                  : _prices!.join('\n'),
              style: body,
            ),
            const SizedBox(height: 8),
            Text('Refund eligibility has been removed for this request.', style: body),
          ] else if (_confirm) ...[
            Text(
              'Viewing competing offers removes your refund eligibility for this request. Only prices will be shown.',
              style: body,
            ),
            const SizedBox(height: 12),
            SellerPrimaryButton(
              label: _busy ? 'Opening…' : 'View prices and give up refund',
              onPressed: _busy ? null : _view,
            ),
            const SizedBox(height: 8),
            SellerSecondaryButton(
              label: 'Keep refund eligibility',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _confirm = false;
                      _error = null;
                    }),
            ),
          ] else
            SellerPrimaryButton(
              label: 'View competing offers',
              onPressed: () => setState(() => _confirm = true),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SellerStateNotice(icon: Icons.info_outline, title: _error!, tone: SellerNoticeTone.error),
            ),
        ],
      ),
    );
  }
}

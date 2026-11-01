import 'package:flutter/material.dart';
import '../../theme/seller_ui_foundation.dart';
import '../../theme/adaptive_palette.dart';

typedef HocatrendsOfferPreference = ({bool enabled, bool eligible});

/// Offer-specific opt-in; only an acknowledged server result changes the switch.
class HocatrendsOfferPanel extends StatefulWidget {
  const HocatrendsOfferPanel({super.key, required this.load, required this.save});
  final Future<HocatrendsOfferPreference> Function() load;
  final Future<HocatrendsOfferPreference> Function(bool) save;
  @override
  State<HocatrendsOfferPanel> createState() => _HocatrendsOfferPanelState();
}

class _HocatrendsOfferPanelState extends State<HocatrendsOfferPanel> {
  HocatrendsOfferPreference? value;
  bool busy = false;
  bool? pending;
  String? error;

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    setState(() { busy = true; error = null; });
    try {
      final loaded = await widget.load();
      if (!mounted) return;
      setState(() => value = loaded);
    } catch (_) {
      if (mounted) setState(() => error = 'Hocatrends preference could not be loaded.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> save(bool enabled) async {
    if (busy) return;
    pending ??= enabled;
    setState(() { busy = true; error = null; });
    try {
      final saved = await widget.save(pending!);
      if (!mounted) return;
      if (saved.enabled != pending) throw StateError('Preference not acknowledged');
      setState(() { value = saved; pending = null; });
    } catch (_) {
      if (mounted) setState(() => error = 'Change was not confirmed. Retry the same preference.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.maybeOf(context) ?? ApprovedReplicaMetrics.resolve(
      brightness: Theme.of(context).brightness, availableWidth: MediaQuery.sizeOf(context).width,
      textScaler: MediaQuery.textScalerOf(context));
    return Container(
      padding: EdgeInsets.all(metrics.spacing(12)),
      decoration: BoxDecoration(color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(11)),
        border: Border.all(color: HocalistPalette.border(context, SellerUiColors.lavenderBorder))),
      child: Material(color: Colors.transparent, child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile.adaptive(
        key: const Key('hocatrends-offer-opt-in'),
        contentPadding: EdgeInsets.zero,
        activeTrackColor: SellerUiColors.primaryBright,
        title: Text('Show this offer on Hocatrends', style: sellerText(metrics, 12, weight: FontWeight.w800)),
        subtitle: Text(value?.eligible == true
            ? 'Let buyers discover you for this category. You can turn this off anytime.'
            : 'Requires Pro or Elite and an eligible recent offer. Your preference is saved separately from eligibility.',
            style: sellerText(metrics, 11, color: SellerUiColors.muted)),
        value: value?.enabled ?? false,
        onChanged: busy || value == null || pending != null ||
            (value?.eligible != true && value?.enabled != true) ? null : save,
      ),
      if (busy) const SellerProgressStrip(label: 'Checking Hocatrends preference…'),
      if (error != null) ...[
        Text(error!, style: sellerText(metrics, 11, color: SellerUiColors.muted)),
        TextButton(key: const Key('hocatrends-preference-retry'),
          onPressed: busy ? null : () => pending == null ? refresh() : save(pending!),
          child: Text('Retry', style: sellerText(metrics, 12, weight: FontWeight.w700, color: SellerUiColors.primaryBright))),
      ],
    ],
  )));
  }
}

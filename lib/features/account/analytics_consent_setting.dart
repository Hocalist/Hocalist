import 'package:flutter/material.dart';

import '../../data/marketplace_analytics.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/buyer_ui_foundation.dart';
import '../approved/approved_replica_metrics.dart';

/// Shared by existing onboarding and Buyer/Seller account settings.
class AnalyticsConsentSetting extends StatefulWidget {
  const AnalyticsConsentSetting({super.key});

  @override
  State<AnalyticsConsentSetting> createState() =>
      _AnalyticsConsentSettingState();
}

class _AnalyticsConsentSettingState extends State<AnalyticsConsentSetting> {
  final _analytics = MarketplaceAnalytics.instance;
  bool? _enabled;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_analytics.supported) _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await _analytics.consent();
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Usage analytics is unavailable on this build.',
        );
      }
    }
  }

  Future<void> _change(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _analytics.setConsent(enabled);
      if (mounted) setState(() => _enabled = enabled);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Your preference could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_analytics.supported) return const SizedBox.shrink();
    final metrics =
        ApprovedReplicaScope.maybeOf(context) ??
        ApprovedReplicaMetrics.resolve(
          brightness: Theme.of(context).brightness,
          availableWidth: MediaQuery.sizeOf(context).width,
          textScaler: MediaQuery.textScalerOf(context),
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.spacing(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Share usage analytics (optional)',
                  style: BuyerTypography.style(
                    context,
                    metrics,
                    BuyerTextRole.cardTitle,
                  ),
                ),
              ),
              SizedBox(width: metrics.spacing(8)),
              Semantics(
                label: 'Share usage analytics',
                child: Switch.adaptive(
                  key: const ValueKey('analytics-consent-switch'),
                  value: _enabled == true,
                  activeTrackColor: HocalistPalette.text(
                    context,
                    BuyerUiTokens.action,
                  ),
                  onChanged: _enabled == null || _busy ? null : _change,
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.spacing(4)),
          Text(
            'Help improve Hocalist by sharing request and seller signup activity '
            'with Google Analytics on this device. Optional and off by default. '
            'You can change this in Account Settings. Messages, addresses and payment details are not included in these events.',
            style: BuyerTypography.style(
              context,
              metrics,
              BuyerTextRole.secondaryBody,
            ),
          ),
          if (_busy) const BuyerProgressStrip(label: 'Saving preference…'),
          if (_error != null) ...[
            SizedBox(height: metrics.spacing(8)),
            BuyerStateNotice(
              icon: Icons.info_outline,
              tone: BuyerNoticeTone.error,
              title: 'Analytics preference',
              body: _error,
            ),
          ],
        ],
      ),
    );
  }
}

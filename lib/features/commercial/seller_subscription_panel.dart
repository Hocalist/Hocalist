import '../../components/pull_refresh.dart';
import 'package:hocalist/components/hocalist_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/phase2/providers/stripe_test_billing_service.dart';
import '../../data/phase2/commercial/entitlement_backend.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/seller_ui_foundation.dart';
import 'seller_plan_summary.dart';

/// Read-only subscription status; credit batches and weekly slots stay separate.
class SellerSubscriptionPanel extends StatefulWidget {
  const SellerSubscriptionPanel({this.load, this.loadEntitlement, super.key});

  final Future<Map<String, dynamic>?> Function()? load;
  final Future<SellerEntitlementView> Function()? loadEntitlement;

  @override
  State<SellerSubscriptionPanel> createState() =>
      _SellerSubscriptionPanelState();
}

class _SellerSubscriptionPanelState extends State<SellerSubscriptionPanel> {
  Map<String, dynamic>? _status;
  SellerEntitlementView? _entitlement;
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final entitlementLoader =
          widget.loadEntitlement ??
          (widget.load == null
              ? createConfiguredEntitlementBackend()?.loadEntitlement
              : null);
      if (entitlementLoader != null) {
        final result = await entitlementLoader();
        if (!mounted || generation != _generation) return;
        setState(() {
          _entitlement = result;
          _status = null;
          _loading = false;
        });
        return;
      }
      final result =
          await (widget.load ??
              StripeTestBillingService(Supabase.instance.client).fetchStatus)();
      if (!mounted || generation != _generation) return;
      if (result != null &&
          !{'free', 'pro', 'elite'}.contains(result['plan'])) {
        throw const FormatException('Invalid plan');
      }
      setState(() {
        _status = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = null;
        _entitlement = null;
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PullRefreshAction(onRefresh: _loading ? null : _load, child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const SellerStateNotice(
        icon: Icons.workspace_premium_outlined,
        title: 'Loading your plan…',
        trailing: HocalistLoadingIndicator(),
      );
    }
    if (_failed) {
      return SellerStateNotice(
        icon: Icons.error_outline,
        title: 'Could not load your plan',
        body: 'Try again to read your current subscription.',
        tone: SellerNoticeTone.error,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    final entitlement = _entitlement;
    if (entitlement != null) {
      return SellerPlanSummary(value: entitlement);
    }
    final status = _status;
    if (status == null) {
      return const SellerStateNotice(
        icon: Icons.workspace_premium_outlined,
        title: 'Seller subscription unavailable',
        body: 'No seller subscription record was returned.',
      );
    }
    final plan = switch (status['plan']) {
      'pro' => 'Pro',
      'elite' => 'Elite',
      _ => 'Free',
    };
    final review = status['requires_review'] == true;
    return SellerStateNotice(
      icon: Icons.workspace_premium_outlined,
      title: '$plan Seller plan',
      tone: review ? SellerNoticeTone.warning : SellerNoticeTone.brand,
      body: review
          ? 'Your billing record needs review. Paid access is not confirmed.'
          : status['plan'] == 'free'
          ? 'No active paid subscription. Credit batches and weekly targeting capacity are separate from your plan.'
          : 'Stripe TEST subscription confirmed. Credit batches and weekly targeting capacity are separate from your plan.',
      detail: status['cancel_at_period_end'] == true
          ? const Text(
              'Cancellation is scheduled at the end of the paid period.',
            )
          : null,
    );
  }
}

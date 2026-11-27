import 'package:flutter/material.dart';

import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/seller_ui_foundation.dart';
import 'approved_billing_artwork.dart';
import 'seller_fee_copy.dart';
import 'seller_payment_panel.dart';

class SellerPlanSummary extends StatelessWidget {
  const SellerPlanSummary({
    required this.value,
    this.focusManagePlans = false,
    this.openBilling,
    super.key,
  });

  final SellerEntitlementView value;
  final bool focusManagePlans;
  final Future<bool> Function(Uri)? openBilling;

  @override
  Widget build(BuildContext context) {
    final plans = {for (final limits in value.plans) limits.planCode: limits};
    return _RevealManagePlans(
      reveal: focusManagePlans,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seller plans',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Compare seller benefits. Review subscription prices and billing options on Hocalist.',
                ),
              ],
            ),
          ),
          for (final plan in PlanCode.values) ...[
            _SellerPlanCard(
              key: ValueKey('sellerPlan-${plan.name}'),
              plan: plan,
              value: value,
              limits: plans[plan],
              openBilling: openBilling,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _SellerPlanCard extends StatelessWidget {
  const _SellerPlanCard({
    required this.plan,
    required this.value,
    required this.limits,
    required this.openBilling,
    super.key,
  });

  final PlanCode plan;
  final SellerEntitlementView value;
  final PlanLimitView? limits;
  final Future<bool> Function(Uri)? openBilling;

  @override
  Widget build(BuildContext context) {
    final current = value.effectivePlan == plan;
    final elite = plan == PlanCode.elite;
    final free = plan == PlanCode.free;
    final billing = value.billing;
    final paidSubscription =
        billing.available &&
        !billing.reviewRequired &&
        const {'active', 'trialing'}.contains(billing.providerStatus) &&
        billing.plan != null &&
        billing.plan != PlanCode.free;
    final name = switch (plan) {
      PlanCode.free => 'Free',
      PlanCode.pro => 'Pro Seller',
      PlanCode.elite => 'Elite Seller',
    };
    final access = switch (value.effectiveSource) {
      EntitlementSource.free => 'Free access',
      EntitlementSource.billing => 'Verified subscription',
      EntitlementSource.admin => 'Approved plan access',
      EntitlementSource.earned => 'Earned Pro · this calendar month',
    };
    final benefits = [
      if (limits != null) ...[
        'Target up to ${limits!.weeklyTargetLimit} different buyers per week',
        'List up to ${limits!.storeListingLimit} products or services',
      ],
      'Seller storefront',
      if (free)
        'Complete ${value.earned.threshold} confirmed sales this month to earn Pro next month',
      if (!free) ...[
        'Withdraw an offer before the buyer responds and recover eligible targeting fees',
        'Save customer contacts after a confirmed sale',
        'Get lead recommendations matched to your listings',
        'Publish eligible listings to Hocatrends',
        'Save on targeting fees',
      ],
      if (elite) ...[
        'Customer insights before sending an offer',
        'View competing offers after buyer acceptance',
        eliteNoPurchaseWaiver,
      ],
    ];
    final billingLabel = switch (plan) {
      PlanCode.free => paidSubscription ? 'Switch to Free' : 'View Free plan',
      _ when paidSubscription && billing.plan == plan => 'Manage $name',
      _ when paidSubscription => 'Switch to $name',
      _ => 'Choose $name',
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: HocalistPalette.border(context, SellerUiColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: HocalistPalette.surface(
              context,
              elite ? SellerUiColors.amberSurface : SellerUiColors.lavender,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (current) ...[
                          const SellerPlanBadge(label: 'CURRENT PLAN'),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (current || free)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              free && !current ? 'No subscription fee' : access,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!free)
                    ApprovedBillingArtwork(
                      source:
                          'assets/approved_seller/billing/${plan.name}-reference.jpg',
                      crop: const Rect.fromLTWH(590, 230, 205, 185),
                      size: 64,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final benefit in benefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: HocalistPalette.text(
                            context,
                            SellerUiColors.primary,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(child: Text(benefit)),
                      ],
                    ),
                  ),
                if (free && current && value.earned.currentWindow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${value.earned.currentWindow!.sales} / ${value.earned.threshold} confirmed sales this month',
                    ),
                  ),
                if (free && current && !paidSubscription)
                  const SellerPrimaryButton(
                    label: 'Current Free plan',
                    onPressed: null,
                  )
                else
                  SellerPaymentPanel(
                    key: ValueKey('billingChoose-${plan.name}'),
                    plan: plan,
                    label: billingLabel,
                    open: openBilling,
                    compact: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RevealManagePlans extends StatefulWidget {
  const _RevealManagePlans({required this.reveal, required this.child});

  final bool reveal;
  final Widget child;

  @override
  State<_RevealManagePlans> createState() => _RevealManagePlansState();
}

class _RevealManagePlansState extends State<_RevealManagePlans> {
  @override
  void initState() {
    super.initState();
    if (widget.reveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

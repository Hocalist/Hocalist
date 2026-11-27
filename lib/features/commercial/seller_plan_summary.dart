import 'package:flutter/material.dart';

import '../../components/hocalist_motion.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/seller_ui_foundation.dart';
import 'approved_billing_artwork.dart';
import 'seller_fee_copy.dart';
import 'seller_payment_panel.dart';

class SellerPlanSummary extends StatefulWidget {
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
  State<SellerPlanSummary> createState() => _SellerPlanSummaryState();
}

class _SellerPlanSummaryState extends State<SellerPlanSummary> {
  final _planAnchors = {for (final plan in PlanCode.values) plan: GlobalKey()};

  void _showPlan(PlanCode plan) {
    final anchor = _planAnchors[plan]?.currentContext;
    if (anchor == null) return;
    Scrollable.ensureVisible(
      anchor,
      alignment: 0.03,
      duration: HocalistMotion.duration(context, 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final plans = {for (final limits in value.plans) limits.planCode: limits};
    return _RevealManagePlans(
      reveal: widget.focusManagePlans,
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
                const SizedBox(height: 14),
                _SellerPlanComparison(plans: plans, onShowPlan: _showPlan),
              ],
            ),
          ),
          for (final plan in PlanCode.values) ...[
            KeyedSubtree(
              key: _planAnchors[plan],
              child: _SellerPlanCard(
                key: ValueKey('sellerPlan-${plan.name}'),
                plan: plan,
                value: value,
                limits: plans[plan],
                openBilling: widget.openBilling,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _SellerPlanComparison extends StatelessWidget {
  const _SellerPlanComparison({required this.plans, required this.onShowPlan});

  final Map<PlanCode, PlanLimitView> plans;
  final ValueChanged<PlanCode> onShowPlan;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    final headingStyle = labelStyle?.copyWith(fontWeight: FontWeight.w800);
    final border = HocalistPalette.border(context, SellerUiColors.line);
    return Material(
      color: HocalistPalette.surface(context, SellerUiColors.lavender),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text('Plan', style: headingStyle)),
                Expanded(
                  child: Text('Unique buyers / week', style: headingStyle),
                ),
                Expanded(child: Text('Store listings', style: headingStyle)),
                const SizedBox(width: 16),
              ],
            ),
          ),
          for (final (plan, limits) in PlanCode.values.map(
            (plan) => (plan, plans[plan]),
          )) ...[
            Divider(height: 1, thickness: 1, color: border),
            InkWell(
              key: ValueKey('compareSellerPlan-${plan.name}'),
              onTap: () => onShowPlan(plan),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (plan) {
                            PlanCode.free => 'Free',
                            PlanCode.pro => 'Pro',
                            PlanCode.elite => 'Elite',
                          },
                          style: headingStyle?.copyWith(
                            color: HocalistPalette.text(
                              context,
                              SellerUiColors.primary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          limits?.weeklyTargetLimit.toString() ?? '—',
                          semanticsLabel: limits == null
                              ? 'Weekly buyer limit unavailable'
                              : '${limits.weeklyTargetLimit} different buyers per week',
                        ),
                      ),
                      Expanded(
                        child: Text(
                          limits?.storeListingLimit.toString() ?? '—',
                          semanticsLabel: limits == null
                              ? 'Store listing limit unavailable'
                              : '${limits.storeListingLimit} store listings',
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ),
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

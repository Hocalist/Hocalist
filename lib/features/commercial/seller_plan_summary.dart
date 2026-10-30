import 'package:flutter/material.dart';
import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/seller_ui_foundation.dart';
import 'approved_billing_artwork.dart';
import 'seller_payment_panel.dart';

class SellerPlanSummary extends StatelessWidget {
  const SellerPlanSummary({required this.value, super.key});
  final SellerEntitlementView value;
  @override
  Widget build(BuildContext context) {
    final plan = value.effectivePlan, elite = plan == PlanCode.elite;
    final name = switch (plan) {
      PlanCode.free => 'Free',
      PlanCode.pro => 'Pro Seller',
      PlanCode.elite => 'Elite Seller',
    };
    final limits = value.plans.where((p) => p.planCode == plan).firstOrNull;
    final rows = <String>[
      if (limits != null)
        'Target up to ${limits.weeklyTargetLimit} weekly customers',
      if (limits != null)
        'List up to ${limits.storeListingLimit} products or services',
      if (plan == PlanCode.free)
        'Complete ${value.earned.threshold} confirmed sales this month to earn Pro next month',
      if (plan == PlanCode.free) 'Seller storefront',
      if (plan != PlanCode.free) ...[
        'Offer withdrawal before the buyer responds',
        'Contacts dashboard',
        'Recommended leads',
        'Get listed on Hocatrends',
        'More savings on targeting fees',
      ],
      if (elite) ...[
        'Refunds when no purchase is confirmed',
        'View competing offers after buyer acceptance',
        'Customer insights',
      ],
    ];
    final artworkIndices = <int>[
      if (limits != null) ...[0, 1],
      if (plan == PlanCode.free) ...[2, 3],
      if (plan != PlanCode.free) ...[2, 3, 4, 5, 6],
      if (elite) ...[7, 8, 9],
    ];
    final source =
        'assets/approved_seller/billing/${plan == PlanCode.free
            ? 'free'
            : elite
            ? 'elite'
            : 'pro'}-reference.jpg';
    final subtitle = switch (value.effectiveSource) {
      EntitlementSource.free => 'Free access',
      EntitlementSource.billing => 'Verified subscription',
      EntitlementSource.admin => 'Approved plan access',
      EntitlementSource.earned => 'Earned Pro · this calendar month',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: HocalistPalette.surface(context, Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: SellerUiColors.line),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                color: HocalistPalette.surface(
                  context,
                  elite ? const Color(0xFFFFF9ED) : const Color(0xFFF1F5FF),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CURRENT PLAN',
                            style: TextStyle(
                              color: SellerUiColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(subtitle),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: HocalistPalette.surface(
                                context,
                                const Color(0xFFE3FAEA),
                              ),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(
                                color: Color(0xFF087D40),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (plan != PlanCode.free)
                      ApprovedBillingArtwork(
                        source: source,
                        crop: const Rect.fromLTWH(590, 230, 205, 185),
                        size: 72,
                      ),
                  ],
                ),
              ),
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: i == rows.length - 1
                          ? null
                          : const Border(
                              bottom: BorderSide(color: SellerUiColors.line),
                            ),
                    ),
                    child: Row(
                      children: [
                        ApprovedBillingArtwork(
                          source: source,
                          crop: plan == PlanCode.free
                              ? Rect.fromLTWH(
                                  [
                                    82.0,
                                    275.0,
                                    464.0,
                                    657.0,
                                  ][artworkIndices[i]],
                                  403,
                                  115,
                                  100,
                                )
                              : Rect.fromLTWH(
                                  76,
                                  438 + artworkIndices[i] * 80,
                                  70,
                                  68,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            rows[i],
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (plan == PlanCode.free && value.earned.currentWindow != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${value.earned.currentWindow!.sales} / ${value.earned.threshold} confirmed sales this month',
            ),
          ),
        const SizedBox(height: 14),
        const SellerPaymentPanel(
          label: 'Compare and manage plans',
          compact: true,
        ),
        if (elite)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Viewing competing offers removes refund eligibility for that request. You will be asked before viewing.',
              style: TextStyle(fontSize: 12, color: SellerUiColors.muted),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/seller_ui_foundation.dart';
import '../commercial/money_help.dart';

class SellerOfferFeeGuide extends StatelessWidget {
  const SellerOfferFeeGuide({super.key, required this.plan});

  final PlanCode? plan;

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final elite = plan == PlanCode.elite;
    final planName = switch (plan) {
      PlanCode.free => 'Free',
      PlanCode.pro => 'Pro',
      PlanCode.elite => 'Elite',
      null => null,
    };
    final steps = [
      (
        Icons.edit_note_outlined,
        'Send your offer',
        'If you use HocaCredits, they’re reserved when you send the offer.',
      ),
      (
        Icons.forum_outlined,
        'Connect with the buyer',
        plan == null
            ? 'The timing of the initial lead fee depends on your plan.'
            : elite
            ? 'Your HocaCredits stay reserved while you negotiate.'
            : 'The initial lead fee applies when the buyer replies to your offer.',
      ),
      (
        Icons.emoji_events_outlined,
        'Close the deal',
        elite
            ? 'Use the buyer’s Hocalist PIN to confirm the purchase. The winning fee then applies.'
            : 'Use the buyer’s Hocalist PIN to confirm the purchase. If you already paid the initial lead fee, it counts toward the winning fee.',
      ),
      (
        Icons.refresh,
        'Buyer didn’t confirm a purchase?',
        plan == null
            ? 'See the fee details for your plan’s rules.'
            : elite
            ? 'If the buyer doesn’t confirm a purchase with any seller, eligible reserved HocaCredits are returned.'
            : 'If the buyer replied, you only pay the initial lead fee. The remaining winning fee applies only to a confirmed purchase with you.',
      ),
    ];
    return Container(
      key: const Key('sellerOfferFeeGuide'),
      padding: EdgeInsets.all(metrics.spacing(12)),
      decoration: BoxDecoration(
        color: HocalistPalette.surface(context, SellerUiColors.lavender),
        borderRadius: BorderRadius.circular(metrics.geometry(9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (planName != null)
            Padding(
              padding: EdgeInsets.only(bottom: metrics.spacing(10)),
              child: Text(
                '$planName plan',
                style: sellerText(metrics, 12, weight: FontWeight.w800),
              ),
            ),
          for (final (icon, heading, description) in steps)
            Padding(
              padding: EdgeInsets.only(bottom: metrics.spacing(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    color: HocalistPalette.text(
                      context,
                      SellerUiColors.primaryBright,
                    ),
                    size: metrics.artSize(18),
                  ),
                  SizedBox(width: metrics.geometry(9)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heading,
                          style: sellerText(
                            metrics,
                            12,
                            weight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: metrics.spacing(3)),
                        Text(
                          description,
                          style: sellerText(metrics, 11, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('sellerOfferFeeGuideHelp'),
              onPressed: () => showMoneyHelp(
                context,
                seller: true,
                title: 'Fees and credit protection',
                answers: {
                  if (plan != PlanCode.elite)
                    'Free and Pro':
                        'If the buyer replies, the initial lead fee applies. If the buyer confirms a purchase from you with their PIN, any initial fee already paid counts toward the total winning fee.',
                  if (plan == null || elite)
                    'Elite':
                        'The initial lead fee can apply once a purchase is confirmed with any seller or the seven-day window ends. If nobody confirms a purchase, eligible fees are waived. Viewing competing offers removes the waiver for this request. An existing meetup can keep credits reserved longer.',
                  if (plan == PlanCode.free || plan == PlanCode.pro)
                    'Explore plan benefits':
                        'Go to More → Plans & credits to compare plans.',
                  'Credit rates':
                      'HocaCredit top-ups keep their original rates. Credit releases follow the meeting and expiry rules.',
                },
              ),
              child: const Text('Learn more about fees and credit protection'),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../domain/phase2/commercial/commercial.dart';
import '../../theme/adaptive_palette.dart';
import '../../theme/seller_ui_foundation.dart';
import '../commercial/money_help.dart';
import '../commercial/seller_fee_copy.dart';

class SellerOfferFeeGuide extends StatefulWidget {
  const SellerOfferFeeGuide({
    super.key,
    required this.plan,
    this.preview = false,
  });

  final PlanCode? plan;
  final bool preview;

  @override
  State<SellerOfferFeeGuide> createState() => _SellerOfferFeeGuideState();
}

class _SellerOfferFeeGuideState extends State<SellerOfferFeeGuide> {
  PlanCode? _previewPlan;

  static const _planNames = {
    PlanCode.free: 'Free',
    PlanCode.pro: 'Pro',
    PlanCode.elite: 'Elite',
  };

  @override
  Widget build(BuildContext context) {
    final metrics = ApprovedReplicaScope.of(context);
    final plan = widget.preview
        ? _previewPlan ?? widget.plan ?? PlanCode.free
        : widget.plan;
    final elite = plan == PlanCode.elite;
    final canPullOut = plan == PlanCode.pro || elite;
    final planName = _planNames[plan];
    final steps = [
      (
        Icons.edit_note_outlined,
        'Send your offer',
        'Sending an offer reserves HocaCredits if you pay with credits. The first fee is due later.',
      ),
      (
        Icons.forum_outlined,
        'Connect with the buyer',
        plan == null
            ? 'The timing of the initial lead fee depends on your plan.'
            : elite
            ? 'Your HocaCredits stay reserved while you negotiate. A reply alone doesn’t trigger the first fee.'
            : 'The initial lead fee applies when the buyer replies to your offer. With no reply, there’s no initial fee.',
      ),
      (
        Icons.emoji_events_outlined,
        'Close the deal',
        elite
            ? 'If the buyer confirms a purchase with another seller, the initial fee can apply. If you close the sale with the buyer’s PIN, any initial fee already paid counts toward the winning total.'
            : 'Use the buyer’s Hocalist PIN to confirm the purchase. If you already paid the initial lead fee, it counts toward the winning fee.',
      ),
      (
        Icons.refresh,
        'Buyer didn’t confirm a purchase?',
        plan == null
            ? 'See the fee details for your plan’s rules.'
            : elite
            ? '$eliteNoPurchaseWaiver If you viewed competing offers and the buyer replied, the initial lead fee can apply after the seven-day window. An existing meetup can keep credits reserved longer.'
            : 'If the buyer replied, you only pay the initial lead fee. The remaining winning fee applies only to a confirmed purchase with you.',
      ),
      if (canPullOut)
        (
          Icons.undo_rounded,
          'Pull out before the buyer responds',
          'Withdraw your offer before the buyer responds. Any reserved HocaCredits are released, and you can send another offer while the request is open.',
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
          if (widget.preview) ...[
            Text(
              'Preview a seller plan',
              style: sellerText(metrics, 12, weight: FontWeight.w800),
            ),
            SizedBox(height: metrics.spacing(6)),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in _planNames.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: plan == entry.key,
                    onSelected: (_) => setState(() => _previewPlan = entry.key),
                  ),
              ],
            ),
            SizedBox(height: metrics.spacing(10)),
          ],
          if (planName != null)
            Padding(
              padding: EdgeInsets.only(bottom: metrics.spacing(10)),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '$planName plan',
                    style: sellerText(metrics, 12, weight: FontWeight.w800),
                  ),
                  if (plan == PlanCode.pro)
                    const SellerPlanBadge(label: 'Pro · Offer Pull Out'),
                  if (elite)
                    const SellerPlanBadge(label: 'Elite fee protection'),
                ],
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
                    (planName ?? 'Free and Pro'):
                        'If the buyer replies, the initial lead fee applies. If the buyer confirms a purchase from you with their PIN, any initial fee already paid counts toward the total winning fee.',
                  if (plan == null || elite)
                    'Elite':
                        '$eliteLeadFeeTiming $eliteNoPurchaseWaiver An existing meetup can keep credits reserved longer.',
                  if (canPullOut)
                    'Offer Pull Out':
                        'On Pro and Elite, you can withdraw before the buyer responds. The same rule applies whether you pay with HocaCredits or an eligible card.',
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

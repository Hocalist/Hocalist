import 'package:flutter/material.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/seller_offer_fee_guide.dart';
import 'package:hocalist/main.dart' show HocalistPrototype, HocalistTheme;
import 'package:hocalist/theme/seller_ui_foundation.dart';

// Start the existing marketplace preview directly, without a real account
// session or the production entry point that initializes external services.
void main() {
  const feePreviewOnly = bool.fromEnvironment('HOCALIST_JONS_DEV_FEE_PREVIEW');
  runApp(feePreviewOnly ? const JonsDevApp() : const HocalistPrototype());
}

class JonsDevApp extends StatelessWidget {
  const JonsDevApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hocalist – Jon’s Dev',
    debugShowCheckedModeBanner: false,
    theme: HocalistTheme.light,
    darkTheme: HocalistTheme.dark,
    home: const _SellerOfferPreview(),
  );
}

class _SellerOfferPreview extends StatefulWidget {
  const _SellerOfferPreview();

  @override
  State<_SellerOfferPreview> createState() => _SellerOfferPreviewState();
}

class _SellerOfferPreviewState extends State<_SellerOfferPreview> {
  PlanCode _plan = PlanCode.free;

  void _openOffer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SellerOfferForm(
        lead: const SellerLeadView(
          name: 'Sample buyer',
          initials: 'SB',
          city: 'Brooksville, FL',
          distance: '3 mi',
          request: 'Looking for a dining table',
          description: 'Four seats, with a flexible pickup time.',
          budget: r'$250',
          match: 90,
          purchases: 0,
          lastPurchase: '—',
          meeting: 'Public place',
          avatarColor: Color(0xfff0edff),
          initialColor: Color(0xff1717d5),
        ),
        sellerName: 'Sample seller',
        initialPrice: '225',
        presentation: const SellerOfferPresentation.real(
          initialBid: '1.90 HC',
          winningBid: '4.75 HC',
        ),
        previewFeePlan: _plan,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hocalist – Jon’s Dev')),
    body: SellerResponsivePage(
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            'Seller offer preview',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text('Sample data only'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final (plan, label) in const [
                (PlanCode.free, 'Free'),
                (PlanCode.pro, 'Pro'),
                (PlanCode.elite, 'Elite'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _plan == plan,
                  onSelected: (_) => setState(() => _plan = plan),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '5 · How it works',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SellerOfferFeeGuide(plan: _plan),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _openOffer,
            child: const Text('Open Send offer'),
          ),
        ],
      ),
    ),
  );
}

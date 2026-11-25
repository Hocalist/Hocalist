import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/commercial/commercial.dart';
import 'package:hocalist/domain/phase2/customers.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/seller_offer_fee_guide.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';

void main() {
  testWidgets('the guide shows subscription-specific rules and badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SellerResponsivePage(
      builder: (_, _) => const SingleChildScrollView(
        child: SellerOfferFeeGuide(plan: null, preview: true),
      ),
    ))));
    await tester.pumpAndSettle();

    const reply =
        'The initial lead fee applies when the buyer replies to your offer.';
    const reserved = 'Your HocaCredits stay reserved while you negotiate.';
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.textContaining(reply), findsOneWidget);
    expect(find.text('Pull out before the buyer responds'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Pro plan'), findsOneWidget);
    expect(find.textContaining(reply), findsOneWidget);
    expect(find.text('Pro · Offer Pull Out'), findsOneWidget);
    expect(find.text('Pull out before the buyer responds'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Elite'));
    await tester.pumpAndSettle();
    expect(find.text('Elite plan'), findsOneWidget);
    expect(find.textContaining(reserved), findsOneWidget);
    expect(find.textContaining(reply), findsNothing);
    expect(find.text('Elite fee protection'), findsOneWidget);
    expect(find.textContaining('unless you viewed competing offers'), findsOneWidget);

    final help = find.byKey(const Key('sellerOfferFeeGuideHelp'));
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Viewing competing offers removes the waiver for this request'),
      findsOneWidget,
    );
  });

  testWidgets('Free and Pro see the upgrade and only Elite loads lead insights', (tester) async {
    final requested = <String>[];
    var comparisonsOpened = 0;
    Future<void> openOffer(PlanCode plan) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        return TextButton(onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => SellerOfferForm(
            lead: const SellerLeadView(
              requestId: 'sample-request', name: 'Sample buyer', initials: 'SB',
              city: 'Brooksville, FL', distance: '3 mi', request: 'Dining table',
              description: 'A dining table for four.', budget: r'$250', match: 90,
              purchases: 0, lastPurchase: '', meeting: 'Public place',
              avatarColor: Color(0xfff0edff), initialColor: Color(0xff1717d5),
            ),
            sellerName: 'Sample seller',
            presentation: const SellerOfferPresentation.approvedPrototype(),
            previewFeePlan: plan,
            onComparePlans: () => comparisonsOpened++,
            loadLeadInsights: (requestId) async {
              requested.add(requestId);
              return const CustomerHistory(concludedRequests: 12, confirmedPurchases: 8,
                ongoingRequests: 1, completionPercent: 66.7);
            },
          ),
        ), child: const Text('Prepare offer'));
      }))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare offer'));
      await tester.pumpAndSettle();
    }

    await openOffer(PlanCode.free);
    expect(requested, isEmpty);
    expect(find.text('About this customer'), findsOneWidget);
    expect(find.text('Elite only'), findsOneWidget);
    final compare = find.text('Compare plans');
    await tester.ensureVisible(compare);
    await tester.pumpAndSettle();
    await tester.tap(compare);
    await tester.pumpAndSettle();
    expect(comparisonsOpened, 1);
    expect(find.text('About this customer'), findsNothing);
    await openOffer(PlanCode.pro);
    expect(requested, isEmpty);
    expect(find.text('Elite only'), findsOneWidget);
    expect(find.text('This buyer confirmed a purchase on 8 of 12 past requests.'), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await openOffer(PlanCode.elite);
    expect(requested, ['sample-request']);
    final insights = find.text('About this customer');
    await tester.ensureVisible(insights);
    await tester.pumpAndSettle();
    expect(find.text('Elite benefit'), findsOneWidget);
    expect(find.text('Compare plans'), findsNothing);
    expect(find.text('This buyer confirmed a purchase on 8 of 12 past requests.'), findsOneWidget);
    expect(find.text('Send Offer'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/jons_dev_sample_deal.dart';
import 'package:hocalist/features/approved/buyer_deal_card.dart';
import 'package:hocalist/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadHocalistTestFonts);

  Future<void> openPreview(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const HocalistPrototype(sampleDeal: true));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String option) async {
    await tap(tester, find.byTooltip('Switch account'));
    await tap(tester, find.text(option).last);
  }

  testWidgets('each chat menu opens the matching quick report in Jon’s Dev', (
    tester,
  ) async {
    await openPreview(tester);
    await tap(tester, find.byTooltip('Chat with seller'));
    await tap(tester, find.byKey(const Key('approved-chat-more')));
    await tap(tester, find.text('Report seller'));
    await tap(tester, find.text('Choose a reason'));
    await tap(tester, find.text('Offered an illegal product or service'));
    await tap(tester, find.text('Save report'));
    expect(find.text('Report Saved'), findsOneWidget);

    await choose(tester, 'Seller');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Chats').last);
    await tap(tester, find.text(sampleDealRequest.buyerName).first);
    await tap(tester, find.byKey(const Key('approved-chat-more')));
    await tap(tester, find.text('Report buyer'));
    await tap(tester, find.text('Choose a reason'));
    await tap(tester, find.text('Requested an illegal product or service'));
    await tap(tester, find.text('Save report'));
    expect(find.text('Report Saved'), findsOneWidget);
  });

  testWidgets('seller sends the same offer the buyer sees and confirms', (
    tester,
  ) async {
    await openPreview(tester);
    final card = find.byType(BuyerDealCard);
    expect(tester.widget<BuyerDealCard>(card).price, r'$225');
    await choose(tester, 'Reset sample deal');
    expect(find.text('Find Customers'), findsOneWidget);
    await tap(tester, find.text('Prepare offer'));
    final sheet = find.byKey(const Key('sellerSendOfferBottomSheet'));
    final inputs = find.descendant(
      of: sheet,
      matching: find.byType(EditableText),
    );
    await tester.enterText(inputs.first, '210.50');
    await tester.enterText(inputs.at(1), 'Four chairs and free pickup.');
    await tap(tester, find.text('Send Offer'));
    await choose(tester, 'Buyer');
    final received = tester.widget<BuyerDealCard>(card);
    expect(received.price, r'$210.50');
    expect(received.message, 'Four chairs and free pickup.');
    await tap(tester, find.text('Accept offer and meet'));
    await tap(tester, find.text('Confirm meeting'));
    expect(card, findsNothing);
    expect(find.text('Agreed price'), findsOneWidget);
    await choose(tester, 'Seller');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Meets').last);
    expect(
      find.byKey(const ValueKey('sellerRealMeeting-offer-mc-meeting')),
      findsOneWidget,
    );
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('buyer declines through the current offer options', (
    tester,
  ) async {
    await openPreview(tester);
    final accept = find.text('Accept offer and meet');
    await tester.ensureVisible(accept);
    await tester.longPress(accept);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Decline offer'));
    await tap(tester, find.text('Decline offer'));
    expect(find.byType(BuyerDealCard), findsNothing);
    await choose(tester, 'Seller');
    expect(find.text('Declined'), findsWidgets);
  });

  testWidgets('a suggested time is passed to the seller for confirmation', (
    tester,
  ) async {
    await openPreview(tester);
    final accept = find.text('Accept offer and meet');
    await tester.ensureVisible(accept);
    await tester.longPress(accept);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Reschedule'));
    await tap(tester, find.text('OK'));
    await tap(tester, find.text('OK'));
    await choose(tester, 'Seller');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Meets').last);
    expect(find.text('Proposed'), findsOneWidget);
    await tap(tester, find.text('Accept'));
    expect(find.text('Confirmed'), findsOneWidget);
    await choose(tester, 'Buyer');
    expect(find.text('Agreed price'), findsOneWidget);
  });
}

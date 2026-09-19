import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/seller/approved_seller_meets_page.dart';
import 'package:hocalist/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local marketplace snapshot keeps offers and conversation entries', () {
    final repository = LocalMarketplaceRepository();
    repository.submitOffer(_offer());
    repository.addConversationEntry(
      senderIsSeller: true,
      text: 'I can meet at the library.',
    );

    final restored = LocalMarketplaceRepository()
      ..restoreSnapshot(repository.encodeSnapshot());

    expect(restored.latestOffer?.price, r'$512');
    expect(restored.latestOffer?.sellerName, 'Northside Tech');
    expect(restored.conversationEntries.single.text, contains('library'));
    expect(restored.conversationEntries.single.senderIsSeller, isTrue);
  });

  test('legacy destinations are quarantined to upgraded routes', () {
    expect(
      upgradedDestinationFor(AppPage.sendOffer, UserRole.seller),
      AppPage.marketplace,
    );
    expect(
      upgradedDestinationFor(AppPage.offerSuccess, UserRole.seller),
      AppPage.sellerOfferHistory,
    );
    expect(
      upgradedDestinationFor(AppPage.finalizeDeal, UserRole.buyer),
      AppPage.buyerChat,
    );
  });

  testWidgets('submitted offer data reaches the upgraded Buyer offers page', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedOffersReceivedPage(
        onBack: () {},
        onNotifications: () {},
        onViewOffer: () {},
        onChat: () {},
        onFilter: () {},
        navigation: ApprovedBuyerNavigation(
          onHome: () {},
          onHocatrends: () {},
          onOffers: () {},
          onChats: () {},
          onMore: () {},
        ),
        latestOffer: _offer(),
      ),
    );

    expect(find.text('Northside Tech'), findsOneWidget);
    expect(find.text(r'$512'), findsOneWidget);
    expect(find.textContaining('Maya, I have the iPad ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat sends text into the visible upgraded conversation', (
    tester,
  ) async {
    ApprovedConversationEntry? submitted;
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
        onEntrySent: (entry) => submitted = entry,
      ),
    );
    await tester.drag(
      find.byKey(const Key('approved-chat-scroll')),
      const Offset(0, -2200),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('approved-chat-message')),
      'Frontend persistence proof',
    );
    await tester.tap(find.byKey(const Key('approved-chat-send')));
    await tester.pumpAndSettle();

    expect(find.text('Frontend persistence proof'), findsOneWidget);
    expect(submitted?.text, 'Frontend persistence proof');
    expect(submitted?.isOutgoing, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat icon buttons do not reveal a pressed background', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedConversationBody(
        onBack: () {},
        onPrimary: () {},
        onCall: () {},
        onMore: () {},
        onRequestChange: () {},
        onChangeLocation: () {},
        onAttach: () {},
        onSend: (_) {},
        onLearnMore: () {},
      ),
    );
    await tester.drag(
      find.byKey(const Key('approved-chat-scroll')),
      const Offset(0, -2200),
    );
    await tester.pumpAndSettle();

    final send = find.byKey(const Key('approved-chat-send'));
    final style = IconButtonTheme.of(tester.element(send)).style;
    expect(style, isNotNull);
    for (final state in [
      WidgetState.hovered,
      WidgetState.focused,
      WidgetState.pressed,
      WidgetState.selected,
    ]) {
      expect(style!.backgroundColor?.resolve({state}), Colors.transparent);
      expect(style.overlayColor?.resolve({state}), Colors.transparent);
    }
  });

  testWidgets('seller offer sheet selects a local place and submits a record', (
    tester,
  ) async {
    LocalOfferRecord? submitted;
    await _pump(
      tester,
      ApprovedSellerLeadsPage(onOfferSubmitted: (offer) => submitted = offer),
    );

    await tester.tap(find.text('Prepare offer').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('sellerOfferSpecificLocation')),
    );
    await tester.tap(find.byKey(const Key('sellerOfferSpecificLocation')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a public meetup place'), findsOneWidget);
    await tester.tap(find.text('Yonkers Public Library'));
    await tester.pumpAndSettle();

    expect(find.text('Yonkers Public Library'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.tap(find.byKey(const Key('sellerSendOfferSubmit')));
    await tester.pumpAndSettle();

    expect(submitted?.buyerName, 'Maya Chen');
    expect(submitted?.location, 'Yonkers Public Library');
    expect(submitted?.status, LocalOfferStatus.sent);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'seller meeting call and map actions open upgraded local sheets',
    (tester) async {
      await _pump(tester, ApprovedSellerMeetsPage(onOpenChat: () {}));
      await tester.tap(find.byKey(const Key('sellerMeetProductJM')));
      await tester.pumpAndSettle();

      final call = find.byKey(const Key('sellerMeetCall-JM'));
      await tester.ensureVisible(call);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Call'));
      await tester.pumpAndSettle();
      expect(find.text('Call James M.'), findsOneWidget);
      expect(find.textContaining('native phone handoff'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      final map = find.byKey(const Key('sellerMeetMap-JM'));
      await tester.ensureVisible(map);
      await tester.tap(map);
      await tester.pumpAndSettle();
      expect(find.text('Meeting location'), findsWidgets);
      expect(find.textContaining('native map provider'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

LocalOfferRecord _offer() {
  return const LocalOfferRecord(
    id: 'offer-proof',
    requestId: 'request-ipad-air',
    buyerName: 'Maya Chen',
    sellerName: 'Northside Tech',
    requestTitle: 'iPad Air, 5th gen or newer',
    price: r'$512',
    location: 'Yonkers Public Library',
    meetingDate: 'Sat, Aug 29, 2026',
    meetingTime: '3:00 PM',
    message: 'Maya, I have the iPad ready for a public meetup.',
    imageNames: <String>['ipad-front.jpg'],
    status: LocalOfferStatus.sent,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: child)),
  );
  await tester.pumpAndSettle();
}

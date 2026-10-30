import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/chat/conversation_send_feedback.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);

  test('clearing one deal does not clear another conversation or deal', () {
    final feedback = ConversationSendFeedback();
    const a = (conversationId: 'chat', offerId: 'offer-a');
    const b = (conversationId: 'chat', offerId: 'offer-b');
    const other = (conversationId: 'other-chat', offerId: 'offer-a');
    feedback.setError(a, 'A needs payment');
    feedback.setError(b, 'B failed');
    feedback.setError(other, 'Other chat failed');
    feedback.setError(a, null);
    expect(feedback.errorFor(a), isNull);
    expect(feedback.errorFor(b), 'B failed');
    expect(feedback.errorFor(other), 'Other chat failed');
  });

  for (final seller in [false, true]) {
    testWidgets('payment warning stays with its deal, including late results: seller=$seller', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final feedback = ConversationSendFeedback();
      const a = (conversationId: 'chat', offerId: 'offer-a');
      const b = (conversationId: 'chat', offerId: 'offer-b');
      var active = a;
      late StateSetter rebuild;
      feedback.setError(a, 'This deal needs a payment update.');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
        builder: (context, update) {
          rebuild = update;
          return ApprovedConversationBody(
            onBack: () {}, onPrimary: () {}, onCall: () {}, onMore: () {},
            onRequestChange: () {}, onChangeLocation: () {}, onAttach: () {},
            onSend: (_) {}, onLearnMore: () {}, viewerIsSeller: seller,
            realEntries: const [],
            realDeals: const [
              ApprovedDealView(meetingId: 'a',offerId: 'offer-a',title: 'Deal A',priceLabel: '10',statusLabel: 'Waiting'),
              ApprovedDealView(meetingId: 'b',offerId: 'offer-b',title: 'Deal B',priceLabel: '20',statusLabel: 'Waiting'),
            ],
            selectedDealId: active.offerId,
            onSelectRealDeal: (id) => update(() => active = id == 'b' ? b : a),
            sendError: feedback.errorFor(active),
            onManagePayment: active == a ? () {} : null,
          );
        },
      ))));
      await tester.pumpAndSettle();
      expect(find.text('This deal needs a payment update.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('active-deal-b')));
      await tester.pumpAndSettle();
      expect(find.text('Selected deal: Deal B'), findsOneWidget);
      expect(find.text('This deal needs a payment update.'), findsNothing);
      expect(find.byKey(const Key('approvedChatManagePayment')), findsNothing);
      // The first deal's delayed response arrives while the second is open.
      rebuild(() => feedback.setError(a, 'Late payment failure for A.'));
      await tester.pumpAndSettle();
      expect(find.text('Late payment failure for A.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('active-deal-a')));
      await tester.pumpAndSettle();
      expect(find.text('Late payment failure for A.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

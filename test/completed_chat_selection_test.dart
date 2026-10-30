import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  testWidgets(
    'completed selected deal keeps its label instead of falling back to another active deal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovedConversationBody(
              onBack: () {},
              onPrimary: () {},
              onCall: () {},
              onMore: () {},
              onRequestChange: () {},
              onChangeLocation: () {},
              onAttach: () {},
              onSend: (_) {},
              onLearnMore: () {},
              realEntries: const [],
              selectedDealId: 'completed-offer',
              realDeals: const [
                ApprovedDealView(
                  offerId: 'other',
                  title: 'Other deal',
                  priceLabel: '20',
                  statusLabel: 'Meeting pending',
                ),
              ],
              previousDeals: const [
                ApprovedDealView(
                  offerId: 'completed-offer',
                  title: 'Completed deal',
                  priceLabel: '30',
                  statusLabel: 'Purchase completed',
                  completed: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected deal: Completed deal'), findsOneWidget);
      expect(find.text('Selected deal: Other deal'), findsNothing);
      expect(find.text('Completed deal: purchase completed.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

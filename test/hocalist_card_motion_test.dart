import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_motion.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final seller in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'cards enter visibly and respect reduced motion ($seller/$reduced)',
        (tester) async {
          final nav = ApprovedBuyerNavigation(
            onHome: () {},
            onHocatrends: () {},
            onOffers: () {},
            onChats: () {},
            onMore: () {},
          );
          final page = seller
              ? const ApprovedSellerLeadsPage()
              : ApprovedOffersReceivedPage(
                  onBack: () {},
                  onNotifications: () {},
                  onViewOffer: () {},
                  onChat: () {},
                  onFilter: () {},
                  navigation: nav,
                );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 844),
                  disableAnimations: reduced,
                ),
                child: Scaffold(body: page),
              ),
            ),
          );
          final entrance = find.byType(HocalistEntrance).first;
          expect(entrance, findsOneWidget);
          final opacity = find.descendant(
            of: entrance,
            matching: find.byType(Opacity),
          );
          if (reduced) {
            expect(opacity, findsNothing);
          } else {
            expect(tester.widget<Opacity>(opacity.first).opacity, lessThan(1));
            // Visibility is measured after layout; start the first reveal frame.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 130));
            final middle = tester.widget<Opacity>(opacity.first).opacity;
            expect(middle, greaterThan(0));
            expect(middle, lessThan(1));
            await tester.pumpAndSettle();
            expect(tester.widget<Opacity>(opacity.first).opacity, 1);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

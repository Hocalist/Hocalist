import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/hocalist_motion.dart';
import 'package:hocalist/features/seller/approved_seller_leads_page.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';
import 'package:hocalist/features/approved/buyer_deal_card.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'test_fonts.dart';

void main() {
  setUpAll(loadHocalistTestFonts);
  for (final seller in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'cards enter visibly and respect reduced motion ($seller/$reduced)',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
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
                  realOffers: const [BuyerOfferView(
                    offerId: 'motion-offer', requestId: 'motion-request',
                    revisionId: 'motion-revision', offerRevision: 1,
                    sellerName: 'Test seller', initials: 'TS',
                    requestTitle: 'Camera tripod', priceLabel: '\$35',
                    message: 'Includes carrying bag', meetingLabel: 'Tomorrow',
                    placeLabel: 'Library', status: OfferStatus.submitted,
                  )],
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
          if (!seller) {
            // The approved comparison card is static and visible immediately,
            // including when reduced motion is enabled.
            await tester.pumpAndSettle();
            final card = find.byType(BuyerDealCard);
            expect(card, findsOneWidget);
            await tester.scrollUntilVisible(
              find.text('Test seller'), 150,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.text('Test seller').hitTestable(), findsOneWidget);
            expect(tester.widget<BuyerDealCard>(card).title, 'Camera tripod');
            expect(find.descendant(of: card,
                matching: find.byType(HocalistEntrance)), findsNothing);
            expect(tester.takeException(), isNull);
            return;
          }
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

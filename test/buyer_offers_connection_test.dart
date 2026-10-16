// Buyer offers connection tests: real offer cards, list states and the real
// detail selection surface. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/features/approved/offers_chat_pages.dart';

import 'test_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1917ff)),
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

BuyerOfferView _view({
  String offerId = '40000000-0000-4000-8000-000000000001',
  String sellerName = 'Seller B',
  String priceLabel = r'$420',
  String message = 'Can meet tomorrow.',
  String meetingLabel = 'Thu, Oct 1 · 6:30 PM',
  OfferStatus status = OfferStatus.submitted,
  bool purchaseSelected = false,
  DateTime? requestAcceptanceExpiresAt,
}) => BuyerOfferView(
  offerId: offerId,
  requestId: '30000000-0000-4000-8000-000000000001',
  revisionId: '41000000-0000-4000-8000-000000000001',
  offerRevision: 1,
  sellerName: sellerName,
  initials: 'SB',
  priceLabel: priceLabel,
  message: message,
  meetingLabel: meetingLabel,
  placeLabel: 'Cross County Mall',
  status: status,
  purchaseSelected: purchaseSelected,
  requestAcceptanceExpiresAt: requestAcceptanceExpiresAt,
);

ApprovedBuyerNavigation _navigation() => ApprovedBuyerNavigation(
  onHome: () {},
  onHocatrends: () {},
  onOffers: () {},
  onChats: () {},
  onMore: () {},
);

void main() {
  setUpAll(loadHocalistTestFonts);

  testWidgets(
    'real budget filter includes the maximum and excludes higher offers',
    (tester) async {
      await _pump(
        tester,
        ApprovedOffersReceivedPage(
          onBack: () {},
          onNotifications: () {},
          onViewOffer: () {},
          onChat: () {},
          onFilter: () {},
          navigation: _navigation(),
          budgetMaximum: 40,
          realOffers: [
            _view(sellerName: 'Within budget', priceLabel: r'$40'),
            _view(
              offerId: '40000000-0000-4000-8000-000000000002',
              sellerName: 'Over budget',
              priceLabel: r'$41',
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('approved-offers-filter')));
      await tester.pumpAndSettle();
      expect(find.text(r'Offers under $400'), findsNothing);
      await tester.tap(
        find.byKey(const Key('approved-offers-under-400-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approved-offers-apply-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Within budget'), findsOneWidget);
      expect(find.text('Over budget'), findsNothing);
    },
  );

  testWidgets('real offers replace the prototype cards', (tester) async {
    await _pump(
      tester,
      ApprovedOffersReceivedPage(
        onBack: () {},
        onNotifications: () {},
        onViewOffer: () {},
        onChat: () {},
        onFilter: () {},
        navigation: _navigation(),
        realOffers: [_view(sellerName: 'Loop Resale', priceLabel: r'$390')],
        onOpenOffer: (_) {},
      ),
    );
    expect(find.text('Loop Resale'), findsOneWidget);
    expect(find.text(r'$390'), findsOneWidget);
    expect(find.text('Northside Tech'), findsNothing);
  });

  testWidgets('real offers show loading, error and empty states', (
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
        navigation: _navigation(),
        realOffers: const [],
        offersLoading: true,
        offersError: 'Could not load offers. Pull to retry.',
        onRefreshOffers: () {},
      ),
    );
    expect(find.byKey(const Key('approvedOffersLoading')), findsOneWidget);

    await _pump(
      tester,
      ApprovedOffersReceivedPage(
        onBack: () {},
        onNotifications: () {},
        onViewOffer: () {},
        onChat: () {},
        onFilter: () {},
        navigation: _navigation(),
        realOffers: const [],
        offersError: 'Could not load offers. Pull to retry.',
        onRefreshOffers: () {},
      ),
    );
    expect(find.byKey(const Key('approvedOffersError')), findsOneWidget);
    expect(find.byKey(const Key('approvedOffersRetry')), findsOneWidget);

    await _pump(
      tester,
      ApprovedOffersReceivedPage(
        onBack: () {},
        onNotifications: () {},
        onViewOffer: () {},
        onChat: () {},
        onFilter: () {},
        navigation: _navigation(),
        realOffers: const [],
        onRefreshOffers: () {},
      ),
    );
    expect(find.byKey(const Key('approvedOffersEmpty')), findsOneWidget);
  });

  testWidgets('opening a real offer reports its identity', (tester) async {
    BuyerOfferView? opened;
    await _pump(
      tester,
      ApprovedOffersReceivedPage(
        onBack: () {},
        onNotifications: () {},
        onViewOffer: () {},
        onChat: () {},
        onFilter: () {},
        navigation: _navigation(),
        realOffers: [_view()],
        onOpenOffer: (view) => opened = view,
      ),
    );
    await tester.ensureVisible(find.text('View offer details').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View offer details').first);
    await tester.pumpAndSettle();
    expect(opened?.offerId, '40000000-0000-4000-8000-000000000001');
  });

  testWidgets('the real detail page selects the authoritative offer', (
    tester,
  ) async {
    var selected = 0;
    await _pump(
      tester,
      ApprovedViewOfferPage(
        onBack: () {},
        onNotifications: () {},
        onSelectSeller: () => selected += 1,
        onViewProfile: () {},
        navigation: _navigation(),
        realOffer: _view(),
      ),
    );
    expect(find.text('Seller B'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('approved-select-seller')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approved-select-seller')));
    await tester.pumpAndSettle();
    expect(selected, 1);

    await _pump(
      tester,
      ApprovedViewOfferPage(
        onBack: () {},
        onNotifications: () {},
        onSelectSeller: () => selected += 1,
        onViewProfile: () {},
        navigation: _navigation(),
        realOffer: _view(status: OfferStatus.withdrawn),
      ),
    );
    expect(
      find.byKey(const Key('approved-offer-closed-notice')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('approved-select-seller')), findsNothing);
    expect(selected, 1);
  });

  testWidgets('an accepted offer shows the final-purchase choice', (
    tester,
  ) async {
    var chosen = 0;
    await _pump(
      tester,
      ApprovedViewOfferPage(
        onBack: () {},
        onNotifications: () {},
        onSelectSeller: () {},
        onViewProfile: () {},
        navigation: _navigation(),
        realOffer: _view(
          status: OfferStatus.selected,
          requestAcceptanceExpiresAt: DateTime.utc(2026, 10, 3),
        ),
        onChoosePurchaseSeller: () => chosen += 1,
      ),
    );
    expect(find.byKey(const Key('approved-offer-countdown')), findsOneWidget);
    expect(
      find.byKey(const Key('approved-choose-purchase-seller')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('approved-choose-purchase-seller')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approved-choose-purchase-seller')));
    await tester.pumpAndSettle();
    expect(chosen, 1);

    await _pump(
      tester,
      ApprovedViewOfferPage(
        onBack: () {},
        onNotifications: () {},
        onSelectSeller: () {},
        onViewProfile: () {},
        navigation: _navigation(),
        realOffer: _view(status: OfferStatus.selected, purchaseSelected: true),
        onChoosePurchaseSeller: () => chosen += 1,
      ),
    );
    expect(
      find.byKey(const Key('approved-choose-purchase-seller')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('approved-purchase-seller-title')),
      findsOneWidget,
    );
    expect(chosen, 1);

    expect(find.text('Your chat with this seller is open.'), findsOneWidget);
    expect(
      find.text('Chat opens only after you select this seller.'),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('PIN hidden until your meeting is confirmed'),
      findsNothing,
    );
  });

  testWidgets('selection state and errors are shown on the detail page', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedViewOfferPage(
        onBack: () {},
        onNotifications: () {},
        onSelectSeller: () {},
        onViewProfile: () {},
        navigation: _navigation(),
        realOffer: _view(),
        selectionBusy: true,
        selectionError: 'The selection could not be confirmed.',
      ),
    );
    expect(find.text('Selecting…'), findsOneWidget);
    expect(find.byKey(const Key('approvedSelectSellerError')), findsOneWidget);
  });

  testWidgets('real offer list never shows fixture match, reward or count', (
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
        navigation: _navigation(),
        realOffers: [_view(sellerName: 'Loop Resale', priceLabel: r'$390')],
        onOpenOffer: (_) {},
      ),
    );
    expect(find.text('Top match'), findsNothing);
    expect(find.text('Verified member'), findsNothing);
    expect(find.text(r'$0.40'), findsNothing);
    expect(find.text('From 2 sellers'), findsNothing);
    expect(find.textContaining('Newest first'), findsOneWidget);
    expect(find.text(r'$0.15–$0.30'), findsOneWidget);
  });

  testWidgets('real offer detail hides sample PIN, reward and trust facts', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovedViewOfferPage(
        onBack: () {},
        onNotifications: () {},
        onSelectSeller: () {},
        onViewProfile: () {},
        navigation: _navigation(),
        realOffer: _view(),
        requestTitle: 'iPad Air 5 request',
      ),
    );
    expect(find.text('15230'), findsNothing);
    expect(find.text('4.9 (128 reviews)'), findsNothing);
    expect(find.textContaining('230+ successful deals'), findsNothing);
    expect(find.text(r'$12.40'), findsNothing);
    expect(find.text('You have 7 days left'), findsNothing);
    expect(find.text('Your purchase PIN'), findsOneWidget);
    expect(find.text(r'$0.15–$0.30'), findsOneWidget);
    expect(find.text('Meet-up place'), findsOneWidget);
    expect(find.text('Cross County Mall'), findsOneWidget);
    expect(find.text('iPad Air 5 request'), findsOneWidget);
  });

  testWidgets('the view model maps an authoritative offer', (tester) async {
    final offer = Offer(
      id: '40000000-0000-4000-8000-000000000009',
      requestId: '30000000-0000-4000-8000-000000000001',
      buyerUserId: 'user-a',
      sellerProfileId: '10000000-0000-4000-8000-00000000000b',
      sellerUserId: 'user-b',
      sellerDisplayName: 'Northside Tech',
      revisions: [
        OfferRevision(
          id: '41000000-0000-4000-8000-000000000009',
          offerId: '40000000-0000-4000-8000-000000000009',
          sequence: 1,
          terms: OfferTerms(
            price: Money(minorUnits: 55000, currencyCode: 'USD'),
            message: 'Includes the charger.',
            schedule: LocalSchedule(
              date: LocalDate(year: 2026, month: 10, day: 1),
              startTime: LocalTime(hour: 15, minute: 0),
              timezoneId: 'America/New_York',
            ),
            place: MeetingPlace(
              choice: MeetupPlaceChoice.specificPlace,
              label: 'Cross County Mall',
            ),
          ),
          status: OfferRevisionStatus.proposed,
          proposedByUserId: 'user-b',
          createdAt: DateTime.utc(2026, 5, 1),
        ),
      ],
      status: OfferStatus.submitted,
      stamp: RecordStamp(
        revision: 3,
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
    );
    final view = BuyerOfferView.fromOffer(offer);
    expect(view.sellerName, 'Northside Tech');
    expect(view.initials, 'NT');
    expect(view.priceLabel, r'$550');
    expect(view.offerRevision, 3);
    expect(view.revisionId, '41000000-0000-4000-8000-000000000009');
    expect(view.meetingLabel, contains('Oct 1'));
    expect(view.meetingLabel, contains('3:00 PM'));
    expect(view.placeLabel, 'Cross County Mall');
    expect(view.isSelectable, isTrue);
  });
}

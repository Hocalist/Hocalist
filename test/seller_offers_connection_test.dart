// Seller offers backend and surface tests: own-offer reads, withdrawal,
// revision checks and real-mode rows. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_seller_offers_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/schedule.dart';
import 'package:hocalist/features/seller/approved_seller_account_pages.dart';
import 'package:hocalist/features/seller/seller_offer_revision_editor.dart';

import 'phase2/marketplace/support/marketplace_fakes.dart';
import 'test_fonts.dart';

Offer _offer({
  OfferStatus status = OfferStatus.submitted,
  int revision = 1,
  String message = 'Can meet tomorrow.',
}) => Offer(
  id: offerId,
  requestId: requestId,
  buyerUserId: buyerId,
  sellerProfileId: sellerProfileId,
  sellerUserId: sellerId,
  sellerDisplayName: 'Seller B',
  revisions: [
    OfferRevision(
      id: revisionId,
      offerId: offerId,
      sequence: 1,
      terms: OfferTerms(
        price: Money(minorUnits: 42000, currencyCode: 'USD'),
        message: message,
        schedule: LocalSchedule(
          date: LocalDate(year: 2026, month: 10, day: 1),
          startTime: LocalTime(hour: 18, minute: 30),
          timezoneId: 'America/New_York',
        ),
        place: MeetingPlace(
          choice: MeetupPlaceChoice.specificPlace,
          label: 'Cross County Mall',
        ),
      ),
      status: OfferRevisionStatus.proposed,
      proposedByUserId: sellerId,
      createdAt: DateTime.utc(2026, 5, 1),
    ),
  ],
  status: status,
  stamp: RecordStamp(
    revision: revision,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
  ),
);

class FakeSellerOffersBackend implements MarketplaceSellerOffersBackend {
  Future<List<Offer>> Function()? onLoad;
  Future<Offer> Function(String offerId, int revision, String key)? onWithdraw;
  final List<String> withdrawKeys = <String>[];

  @override
  Future<List<Offer>> loadSellerOffers() =>
      onLoad?.call() ?? Future.value(const <Offer>[]);

  @override
  Future<Offer> withdrawOffer({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  }) {
    withdrawKeys.add(operationKey);
    return onWithdraw?.call(offerId, expectedOfferRevision, operationKey) ??
        Future.value(_offer(status: OfferStatus.withdrawn, revision: 2));
  }
}

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
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadHocalistTestFonts);

  group('Phase2MarketplaceSellerOffersBackend', () {
    late FakeMarketplaceSession session;
    late FakeMarketplaceTransport transport;
    late MarketplaceDataAdapter adapter;
    late Phase2MarketplaceSellerOffersBackend backend;

    setUp(() {
      session = FakeMarketplaceSession(sellerId);
      transport = FakeMarketplaceTransport();
      adapter = MarketplaceDataAdapter(transport: transport, session: session);
      backend = Phase2MarketplaceSellerOffersBackend(
        adapter: adapter,
        sellerUserId: sellerId,
      );
    });

    test('loads every own-offer page', () async {
      var pages = 0;
      transport.handler = (call) {
        pages += 1;
        return MarketplaceTransportData(
          pageJson([offerJson()], cursor: pages == 1 ? 'next' : null),
        );
      };
      final offers = await backend.loadSellerOffers();
      expect(offers, hasLength(2));
      expect(transport.calls.first.function, 'marketplace_my_offers');
      expect(transport.calls.last.params['p_cursor'], 'next');
    });

    test('withdraw sends the expected revision and key', () async {
      transport.handler = (call) =>
          MarketplaceTransportData(offerJson(status: 'withdrawn', revision: 2));
      final withdrawn = await backend.withdrawOffer(
        offerId: offerId,
        expectedOfferRevision: 1,
        operationKey: 'withdraw-1',
      );
      expect(withdrawn.status, OfferStatus.withdrawn);
      final call = transport.calls.single;
      expect(call.params['p_operation'], 'offer.withdraw');
      expect(call.params['p_key'], 'withdraw-1');
      final input = call.params['p_input']! as Map<String, Object?>;
      expect(input['offer_id'], offerId);
      expect(input['expected_offer_revision'], 1);
    });

    test(
      'revision sends complete preserved terms with carried revision and key',
      () async {
        transport.handler = (_) =>
            MarketplaceTransportData(offerJson(revision: 2));
        final prior = _offer();
        final terms = prior.latestRevision.terms.copyWith(
          price: Money(minorUnits: 43050, currencyCode: 'USD'),
          message: 'Can meet after six.',
        );
        final revised = await backend.reviseOffer(
          offerId: prior.id,
          expectedOfferRevision: 1,
          terms: terms,
          operationKey: 'revise-1',
        );
        expect(revised.stamp.revision, 2);
        final call = transport.calls.single;
        expect(call.params['p_operation'], 'offer.revise');
        expect(call.params['p_key'], 'revise-1');
        final input = call.params['p_input']! as Map<String, Object?>;
        expect(input['expected_offer_revision'], 1);
        expect(input['price_minor'], 43050);
        expect(input['schedule_timezone'], 'America/New_York');
        expect(input['place_label'], 'Cross County Mall');
      },
    );

    test('maps a conflict to a definitive failure', () async {
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.server,
        message: 'revision_conflict',
        code: 'P0001',
      );
      await expectLater(
        backend.withdrawOffer(
          offerId: offerId,
          expectedOfferRevision: 1,
          operationKey: 'withdraw-2',
        ),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.ambiguous,
            'ambiguous',
            isFalse,
          ),
        ),
      );
    });
  });

  group('LocalMarketplaceRepository seller offers', () {
    test('loads and withdraws with an authoritative update', () async {
      final backend = FakeSellerOffersBackend()
        ..onLoad = () async => [_offer()];
      final repository = LocalMarketplaceRepository(
        sellerOffersBackend: backend,
      );
      await repository.refreshSellerOffers();
      expect(repository.sellerOffers, hasLength(1));

      final result = await repository.withdrawSellerOffer(
        offerId: offerId,
        expectedOfferRevision: 1,
        operationKey: 'w-1',
      );
      expect(result.isSuccess, isTrue);
      expect(result.offer!.status, OfferStatus.withdrawn);
      expect(repository.sellerOffers.single.status, OfferStatus.withdrawn);
      expect(backend.withdrawKeys, ['w-1']);
    });

    test(
      'reports an uncertain withdrawal without changing cached state',
      () async {
        final backend = FakeSellerOffersBackend()
          ..onLoad = () async => [_offer()];
        backend.onWithdraw = (_, _, _) async =>
            throw const StoreBackendException(
              'The change could not be confirmed. Retry to check it safely.',
              ambiguous: true,
            );
        final repository = LocalMarketplaceRepository(
          sellerOffersBackend: backend,
        );
        await repository.refreshSellerOffers();
        final result = await repository.withdrawSellerOffer(
          offerId: offerId,
          expectedOfferRevision: 1,
          operationKey: 'w-2',
        );
        expect(result.isSuccess, isFalse);
        expect(result.outcomeUncertain, isTrue);
        expect(repository.sellerOffers.single.status, OfferStatus.submitted);
      },
    );
  });

  testWidgets('real seller offer history renders rows and opens them', (
    tester,
  ) async {
    SellerOfferView? opened;
    final view = SellerOfferView.fromOffer(
      _offer(),
      requestTitle: 'iPad Air request',
    );
    await _pump(
      tester,
      ApprovedSellerOfferHistoryPage(
        onBack: () {},
        onOpen: () {},
        sellerOfferSent: false,
        offerSelected: false,
        realOffers: [view],
        onOpenOffer: (offer) => opened = offer,
      ),
    );
    expect(find.text('iPad Air request'), findsOneWidget);
    expect(find.text('Waiting for buyer'), findsOneWidget);
    expect(find.text(r'$420'), findsNothing);
    await tester.tap(find.text('iPad Air request'));
    await tester.pumpAndSettle();
    expect(opened?.offerId, offerId);
  });

  testWidgets('real seller offer history shows states', (tester) async {
    await _pump(
      tester,
      ApprovedSellerOfferHistoryPage(
        onBack: () {},
        onOpen: () {},
        sellerOfferSent: false,
        offerSelected: false,
        realOffers: const [],
        offersLoading: true,
      ),
    );
    expect(find.byKey(const Key('sellerOffersLoading')), findsOneWidget);

    await _pump(
      tester,
      ApprovedSellerOfferHistoryPage(
        onBack: () {},
        onOpen: () {},
        sellerOfferSent: false,
        offerSelected: false,
        realOffers: const [],
        offersError: 'Could not load your offers.',
        onRefreshOffers: () {},
      ),
    );
    expect(find.byKey(const Key('sellerOffersError')), findsOneWidget);

    await _pump(
      tester,
      ApprovedSellerOfferHistoryPage(
        onBack: () {},
        onOpen: () {},
        sellerOfferSent: false,
        offerSelected: false,
        realOffers: const [],
      ),
    );
    expect(find.byKey(const Key('sellerOffersEmpty')), findsOneWidget);
  });

  testWidgets('a submitted real offer can be withdrawn', (tester) async {
    var withdrawn = 0;
    await _pump(
      tester,
      ApprovedSellerOfferDetailPage(
        onBack: () {},
        onChat: () {},
        realOffer: SellerOfferView.fromOffer(
          _offer(),
          requestTitle: 'iPad Air request',
        ),
        onWithdraw: () => withdrawn += 1,
      ),
    );
    final withdraw = find.byKey(const Key('sellerOfferWithdraw'));
    await tester.ensureVisible(withdraw);
    await tester.pumpAndSettle();
    await tester.tap(withdraw);
    await tester.pumpAndSettle();
    expect(withdrawn, 1);

    await _pump(
      tester,
      ApprovedSellerOfferDetailPage(
        onBack: () {},
        onChat: () {},
        realOffer: SellerOfferView.fromOffer(
          _offer(status: OfferStatus.withdrawn),
          requestTitle: 'iPad Air request',
        ),
        onWithdraw: () => withdrawn += 1,
      ),
    );
    expect(find.byKey(const Key('sellerOfferWithdraw')), findsNothing);
    expect(find.text('Withdrawn'), findsOneWidget);
  });

  testWidgets(
    'editor freezes an uncertain revision and retries the exact terms',
    (tester) async {
      final intents = <({OfferTerms terms, String key})>[];
      var attempts = 0;
      await _pump(
        tester,
        SellerOfferRevisionEditor(
          offer: _offer(),
          onSave: (terms, key) async {
            intents.add((terms: terms, key: key));
            attempts++;
            return attempts == 1
                ? const SellerOfferActionResult.failure(
                    'Unconfirmed',
                    outcomeUncertain: true,
                  )
                : SellerOfferActionResult.success(_offer(revision: 2));
          },
        ),
      );
      await tester.enterText(
        find.byKey(const Key('sellerOfferRevisionPrice')),
        '430.50',
      );
      await tester.enterText(
        find.byKey(const Key('sellerOfferRevisionMessage')),
        'Can meet after six.',
      );
      await tester.tap(find.byKey(const Key('sellerOfferRevisionSave')));
      await tester.pumpAndSettle();
      expect(find.text('Retry same update'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('sellerOfferRevisionPrice')),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('sellerOfferRevisionSave')));
      await tester.pumpAndSettle();
      expect(intents, hasLength(2));
      expect(intents[0].key, intents[1].key);
      expect(intents[0].terms, intents[1].terms);
      expect(intents[0].terms.price.minorUnits, 43050);
      expect(intents[0].terms.schedule, _offer().latestRevision.terms.schedule);
    },
  );
}

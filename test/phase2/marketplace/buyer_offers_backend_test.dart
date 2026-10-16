// Buyer offers backend tests: per-request reads, selection with conversation
// opening, ambiguous outcomes and repository caching. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_buyer_offers_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/schedule.dart';

import 'support/marketplace_fakes.dart';

class FakeBuyerOffersBackend implements MarketplaceBuyerOffersBackend {
  Future<List<Offer>> Function(String requestId)? onLoad;
  Future<OfferSelectionOutcome> Function(
    String offerId,
    String revisionId,
    int expectedRevision,
    String key,
  )?
  onSelect;
  Future<Offer> Function(String offerId, int expectedRevision, String key)?
  onSelectPurchase;
  final List<String> selectionKeys = <String>[];
  final List<String> purchaseSelectionKeys = <String>[];

  @override
  Future<List<Offer>> loadRequestOffers(String requestId) =>
      onLoad?.call(requestId) ?? Future.value(const <Offer>[]);

  @override
  Future<OfferSelectionOutcome> selectOffer({
    required String offerId,
    required String revisionId,
    required int expectedOfferRevision,
    required String operationKey,
  }) {
    selectionKeys.add(operationKey);
    return onSelect?.call(
          offerId,
          revisionId,
          expectedOfferRevision,
          operationKey,
        ) ??
        Future.value(OfferSelectionOutcome(offer: selectedOffer()));
  }

  @override
  Future<Offer> selectPurchaseSeller({
    required String offerId,
    required int expectedOfferRevision,
    required String operationKey,
  }) {
    purchaseSelectionKeys.add(operationKey);
    return onSelectPurchase?.call(offerId, expectedOfferRevision, operationKey) ??
        Future.value(selectedOffer().copyWith(purchaseSelected: true));
  }
}

Offer selectedOffer({String? conversationId}) {
  final base = decodeOfferForTest();
  return base.copyWith(
    status: OfferStatus.selected,
    acceptedRevisionId: revisionId,
    conversationId: conversationId,
  );
}

Offer decodeOfferForTest() {
  return Offer(
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
        terms: terms(),
        status: OfferRevisionStatus.proposed,
        proposedByUserId: sellerId,
        createdAt: DateTime.utc(2026, 5, 1),
      ),
    ],
    status: OfferStatus.submitted,
    stamp: stamp(),
  );
}

OfferTerms terms() => OfferTerms(
  price: Money(minorUnits: 42000, currencyCode: 'USD'),
  message: 'Can meet tomorrow.',
  schedule: LocalSchedule(
    date: LocalDate(year: 2026, month: 10, day: 1),
    startTime: LocalTime(hour: 18, minute: 30),
    timezoneId: 'America/New_York',
  ),
  place: MeetingPlace(
    choice: MeetupPlaceChoice.specificPlace,
    label: 'Cross County Mall',
  ),
);

RecordStamp stamp({int revision = 1}) => RecordStamp(
  revision: revision,
  createdAt: DateTime.utc(2026, 5, 1),
  updatedAt: DateTime.utc(2026, 5, 1),
);

void main() {
  group('LocalMarketplaceRepository buyer offers', () {
    test('loads and caches request offers', () async {
      final backend = FakeBuyerOffersBackend()
        ..onLoad = (requestId) async => [decodeOfferForTest()];
      final repository = LocalMarketplaceRepository(
        buyerOffersBackend: backend,
      );
      await repository.refreshBuyerOffers(requestId);
      expect(repository.buyerOffers, hasLength(1));
      expect(repository.buyerOffersRequestId, requestId);
      expect(repository.buyerOffersError, isNull);
    });

    test('surfaces a safe offers error', () async {
      final backend = FakeBuyerOffersBackend()
        ..onLoad = (_) async =>
            throw const StoreBackendException('Check your connection.');
      final repository = LocalMarketplaceRepository(
        buyerOffersBackend: backend,
      );
      await repository.refreshBuyerOffers(requestId);
      expect(repository.buyerOffersError, 'Check your connection.');
      expect(repository.buyerOffers, isEmpty);
    });

    test('selection upserts the authoritative offer', () async {
      final backend = FakeBuyerOffersBackend();
      final repository = LocalMarketplaceRepository(
        buyerOffersBackend: backend,
      );
      final result = await repository.selectBuyerOffer(
        offerId: offerId,
        revisionId: revisionId,
        expectedOfferRevision: 1,
        operationKey: 'select-1',
      );
      expect(result.isSuccess, isTrue);
      expect(result.offer!.status, OfferStatus.selected);
      expect(result.conversationId, isNull);
      expect(repository.buyerOffers.single.status, OfferStatus.selected);
      expect(backend.selectionKeys, ['select-1']);
    });

    test('selection reports an uncertain outcome', () async {
      final backend = FakeBuyerOffersBackend()
        ..onSelect = (_, _, _, _) async => throw const StoreBackendException(
          'The selection could not be confirmed. Retry to check it safely.',
          ambiguous: true,
        );
      final repository = LocalMarketplaceRepository(
        buyerOffersBackend: backend,
      );
      final result = await repository.selectBuyerOffer(
        offerId: offerId,
        revisionId: revisionId,
        expectedOfferRevision: 1,
        operationKey: 'select-uncertain',
      );
      expect(result.isSuccess, isFalse);
      expect(result.outcomeUncertain, isTrue);
      expect(repository.buyerOffers, isEmpty);
    });

    test('purchase designation upserts the authoritative offer', () async {
      final backend = FakeBuyerOffersBackend();
      final repository = LocalMarketplaceRepository(
        buyerOffersBackend: backend,
      );
      final result = await repository.selectBuyerPurchaseSeller(
        offerId: offerId,
        expectedOfferRevision: 2,
        operationKey: 'purchase-1',
      );
      expect(result.isSuccess, isTrue);
      expect(result.offer!.purchaseSelected, isTrue);
      expect(repository.buyerOffers.single.purchaseSelected, isTrue);
      expect(backend.purchaseSelectionKeys, ['purchase-1']);
    });

    test('purchase designation reports an uncertain outcome', () async {
      final backend = FakeBuyerOffersBackend()
        ..onSelectPurchase = (_, _, _) async => throw const StoreBackendException(
          'The choice could not be confirmed. Retry to check it safely.',
          ambiguous: true,
        );
      final repository = LocalMarketplaceRepository(
        buyerOffersBackend: backend,
      );
      final result = await repository.selectBuyerPurchaseSeller(
        offerId: offerId,
        expectedOfferRevision: 2,
        operationKey: 'purchase-uncertain',
      );
      expect(result.isSuccess, isFalse);
      expect(result.outcomeUncertain, isTrue);
      expect(repository.buyerOffers, isEmpty);
    });
  });

  group('Phase2MarketplaceBuyerOffersBackend', () {
    late FakeMarketplaceSession session;
    late FakeMarketplaceTransport transport;
    late MarketplaceDataAdapter adapter;
    late Phase2MarketplaceBuyerOffersBackend backend;

    setUp(() {
      session = FakeMarketplaceSession(buyerId);
      transport = FakeMarketplaceTransport();
      adapter = MarketplaceDataAdapter(transport: transport, session: session);
      backend = Phase2MarketplaceBuyerOffersBackend(adapter: adapter);
    });

    test('loads every offer page for one request', () async {
      var pages = 0;
      transport.handler = (call) {
        pages += 1;
        return MarketplaceTransportData(
          pageJson([
            offerJson(),
          ], cursor: pages == 1 ? 'next-offer-page' : null),
        );
      };
      final offers = await backend.loadRequestOffers(requestId);
      expect(offers, hasLength(2));
      expect(transport.calls.first.function, 'marketplace_request_offers');
      expect(transport.calls.first.params['p_request'], requestId);
      expect(transport.calls.last.params['p_cursor'], 'next-offer-page');
    });

    test('selection opens the conversation when the server has none', () async {
      transport.handler = (call) {
        final operation = call.params['p_operation'];
        if (operation == 'offer.select') {
          return MarketplaceTransportData(offerJson());
        }
        if (operation == 'conversation.open_offer') {
          return const MarketplaceTransportData(<String, Object?>{
            'conversation_id': '60000000-0000-4000-8000-000000000001',
          });
        }
        return const MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.server,
          message: 'unexpected',
        );
      };
      final outcome = await backend.selectOffer(
        offerId: offerId,
        revisionId: revisionId,
        expectedOfferRevision: 1,
        operationKey: 'select-key',
      );
      expect(outcome.conversationId, '60000000-0000-4000-8000-000000000001');
      expect(transport.calls, hasLength(2));
      expect(transport.calls.first.params['p_key'], 'select-key');
      final input =
          transport.calls.first.params['p_input']! as Map<String, Object?>;
      expect(input['offer_id'], offerId);
      expect(input['revision_id'], revisionId);
      expect(input['expected_offer_revision'], 1);
      expect(transport.calls.last.params['p_key'], 'select-key-open');
    });

    test(
      'an existing conversation is returned without a second call',
      () async {
        transport.handler = (call) => MarketplaceTransportData(
          offerJson(conversationId: '60000000-0000-4000-8000-000000000002'),
        );
        final outcome = await backend.selectOffer(
          offerId: offerId,
          revisionId: revisionId,
          expectedOfferRevision: 1,
          operationKey: 'select-key',
        );
        expect(outcome.conversationId, '60000000-0000-4000-8000-000000000002');
        expect(transport.calls, hasLength(1));
      },
    );

    test('purchase designation carries the offer and carried revision', () async {
      transport.handler = (call) =>
          MarketplaceTransportData(offerJson(purchaseSelected: true));
      final offer = await backend.selectPurchaseSeller(
        offerId: offerId,
        expectedOfferRevision: 3,
        operationKey: 'purchase-key',
      );
      expect(offer.purchaseSelected, isTrue);
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.function, 'marketplace_command');
      expect(transport.calls.single.params['p_operation'], 'purchase.select');
      expect(transport.calls.single.params['p_key'], 'purchase-key');
      final input =
          transport.calls.single.params['p_input']! as Map<String, Object?>;
      expect(input['offer_id'], offerId);
      expect(input['expected_offer_revision'], 3);
    });

    test('maps a network failure to an ambiguous outcome', () async {
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.connectivity,
        retryable: true,
      );
      await expectLater(
        backend.selectOffer(
          offerId: offerId,
          revisionId: revisionId,
          expectedOfferRevision: 1,
          operationKey: 'k',
        ),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.ambiguous,
            'ambiguous',
            isTrue,
          ),
        ),
      );
    });
  });
}

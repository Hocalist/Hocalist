// Offers/timezone wiring tests: repository state, Phase 2 mapping and the
// resolved schedule contract. Fakes only.
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_codecs.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_offers_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/domain/phase2/common.dart';
import 'package:hocalist/domain/phase2/money.dart';
import 'package:hocalist/domain/phase2/offers.dart';
import 'package:hocalist/domain/phase2/schedule.dart';

import 'support/marketplace_fakes.dart';

class FakeOffersBackend implements MarketplaceOffersBackend {
  Future<List<String>> Function()? onTimezones;
  Future<Offer> Function(String requestId, OfferTerms terms, String key)?
  onSubmit;
  final List<String> submittedKeys = <String>[];
  final List<OfferTerms> submittedTerms = <OfferTerms>[];

  @override
  Future<List<String>> loadTimezones() =>
      onTimezones?.call() ?? Future.value(const ['America/New_York']);

  @override
  Future<Offer> submitOffer({
    required String requestId,
    required OfferTerms terms,
    required String operationKey,
  }) {
    submittedKeys.add(operationKey);
    submittedTerms.add(terms);
    return onSubmit?.call(requestId, terms, operationKey) ??
        Future.value(offer());
  }
}

Offer offer({RepeatedTimeOccurrence? occurrence}) => Offer(
  id: offerId,
  requestId: requestId,
  buyerUserId: buyerId,
  sellerProfileId: sellerProfileId,
  sellerUserId: sellerId,
  revisions: [
    OfferRevision(
      id: revisionId,
      offerId: offerId,
      sequence: 1,
      terms: OfferTerms(
        price: Money(minorUnits: 42000, currencyCode: 'USD'),
        schedule: LocalSchedule(
          date: LocalDate(year: 2026, month: 10, day: 1),
          startTime: LocalTime(hour: 18, minute: 30),
          timezoneId: 'America/New_York',
          occurrence: occurrence,
        ),
        place: MeetingPlace(
          choice: MeetupPlaceChoice.specificPlace,
          label: 'Synthetic Mall',
        ),
      ),
      status: OfferRevisionStatus.proposed,
      proposedByUserId: sellerId,
      createdAt: DateTime.utc(2026, 5, 1),
      resolvedUtcInstant: DateTime.utc(2026, 10, 1, 22, 30),
      resolvedUtcOffsetMinutes: -240,
    ),
  ],
  status: OfferStatus.submitted,
  stamp: RecordStamp(
    revision: 1,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
  ),
);

OfferTerms terms({RepeatedTimeOccurrence? occurrence}) => OfferTerms(
  price: Money(minorUnits: 42000, currencyCode: 'USD'),
  message: 'Synthetic',
  schedule: LocalSchedule(
    date: LocalDate(year: 2026, month: 10, day: 1),
    startTime: LocalTime(hour: 18, minute: 30),
    timezoneId: 'America/New_York',
    occurrence: occurrence,
  ),
  place: MeetingPlace(
    choice: MeetupPlaceChoice.specificPlace,
    label: 'Synthetic Mall',
  ),
);

void main() {
  group('LocalMarketplaceRepository offers', () {
    test('loads and caches server timezones', () async {
      final backend = FakeOffersBackend()
        ..onTimezones = () async => ['America/New_York', 'Europe/London'];
      final repository = LocalMarketplaceRepository(offersBackend: backend);
      await repository.refreshOfferTimezones();
      expect(repository.offerTimezones, ['America/New_York', 'Europe/London']);
      expect(repository.offerTimezonesLoaded, isTrue);
      expect(repository.offerTimezonesError, isNull);
    });

    test('surfaces a safe timezone error', () async {
      final backend = FakeOffersBackend()
        ..onTimezones = () async => throw const StoreBackendException(
          'Check your connection and try again.',
        );
      final repository = LocalMarketplaceRepository(offersBackend: backend);
      await repository.refreshOfferTimezones();
      expect(
        repository.offerTimezonesError,
        'Check your connection and try again.',
      );
      expect(repository.offerTimezones, isEmpty);
    });

    test('submit maps ambiguity and keeps one intent key', () async {
      final backend = FakeOffersBackend();
      var attempts = 0;
      backend.onSubmit = (requestId, offerTerms, key) async {
        attempts += 1;
        if (attempts == 1) {
          throw const StoreBackendException(
            'This local time happens twice. Choose which occurrence applies.',
            code: 'ambiguous_local_time',
          );
        }
        return offer(occurrence: offerTerms.schedule.occurrence);
      };
      final repository = LocalMarketplaceRepository(offersBackend: backend);
      final first = await repository.submitOfferForRequest(
        requestId: requestId,
        terms: terms(),
        operationKey: 'intent-1',
      );
      expect(first.isSuccess, isFalse);
      expect(first.ambiguousTime, isTrue);
      final second = await repository.submitOfferForRequest(
        requestId: requestId,
        terms: terms(occurrence: RepeatedTimeOccurrence.earlier),
        operationKey: 'intent-1',
      );
      expect(second.isSuccess, isTrue);
      expect(backend.submittedKeys, ['intent-1', 'intent-1']);
    });

    test('submit reports an uncertain network outcome', () async {
      final backend = FakeOffersBackend()
        ..onSubmit = (requestId, offerTerms, key) async {
          throw const StoreBackendException(
            'The offer could not be confirmed. Retry to check it safely.',
            ambiguous: true,
          );
        };
      final repository = LocalMarketplaceRepository(offersBackend: backend);
      final result = await repository.submitOfferForRequest(
        requestId: requestId,
        terms: terms(),
        operationKey: 'intent-uncertain',
      );
      expect(result.isSuccess, isFalse);
      expect(result.outcomeUncertain, isTrue);
      expect(result.ambiguousTime, isFalse);
      expect(backend.submittedKeys, ['intent-uncertain']);
    });

    test('a definitive rejection is not reported as uncertain', () async {
      final backend = FakeOffersBackend()
        ..onSubmit = (requestId, offerTerms, key) async {
          throw const StoreBackendException(
            'This local time happens twice. Choose which occurrence applies.',
            code: 'ambiguous_local_time',
          );
        };
      final repository = LocalMarketplaceRepository(offersBackend: backend);
      final result = await repository.submitOfferForRequest(
        requestId: requestId,
        terms: terms(),
        operationKey: 'intent-definitive',
      );
      expect(result.isSuccess, isFalse);
      expect(result.outcomeUncertain, isFalse);
      expect(result.ambiguousTime, isTrue);
    });

    test('submit is unavailable without a backend', () async {
      final repository = LocalMarketplaceRepository();
      await expectLater(
        repository.submitOfferForRequest(
          requestId: requestId,
          terms: terms(),
          operationKey: 'intent-2',
        ),
        throwsA(isA<StoreBackendException>()),
      );
    });
  });

  group('Phase2MarketplaceOffersBackend', () {
    late FakeMarketplaceSession session;
    late FakeMarketplaceTransport transport;
    late MarketplaceDataAdapter adapter;
    late Phase2MarketplaceOffersBackend backend;

    setUp(() {
      session = FakeMarketplaceSession(sellerId);
      transport = FakeMarketplaceTransport();
      adapter = MarketplaceDataAdapter(transport: transport, session: session);
      backend = Phase2MarketplaceOffersBackend(adapter: adapter);
    });

    test('loads named timezones', () async {
      transport.handler = (call) => MarketplaceTransportData(<String, Object?>{
        'items': ['America/New_York', 'Europe/London'],
      });
      final zones = await backend.loadTimezones();
      expect(zones, ['America/New_York', 'Europe/London']);
      expect(transport.calls.single.function, 'marketplace_timezones');
    });

    test('submits the resolved schedule with its occurrence', () async {
      transport.handler = (call) => MarketplaceTransportData(offerJson());
      await backend.submitOffer(
        requestId: requestId,
        terms: terms(occurrence: RepeatedTimeOccurrence.later),
        operationKey: 'offer-key',
      );
      final call = transport.calls.single;
      expect(call.function, 'marketplace_command');
      expect(call.params['p_operation'], 'offer.submit');
      expect(call.params['p_key'], 'offer-key');
      final input = call.params['p_input']! as Map<String, Object?>;
      expect(input['schedule_timezone'], 'America/New_York');
      expect(input['schedule_occurrence'], 'later');
      expect(input['price_minor'], 42000);
    });

    test('maps ambiguous and nonexistent local times to typed codes', () async {
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.server,
        message: 'ambiguous_local_time',
        code: '22023',
      );
      await expectLater(
        backend.submitOffer(
          requestId: requestId,
          terms: terms(),
          operationKey: 'offer-key',
        ),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.code,
            'code',
            'ambiguous_local_time',
          ),
        ),
      );

      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.server,
        message: 'nonexistent_local_time',
        code: '22023',
      );
      await expectLater(
        backend.submitOffer(
          requestId: requestId,
          terms: terms(),
          operationKey: 'offer-key',
        ),
        throwsA(
          isA<StoreBackendException>().having(
            (error) => error.code,
            'code',
            'nonexistent_local_time',
          ),
        ),
      );
    });

    test(
      'duplicate offer explains the existing offer without claiming a changed request',
      () async {
        transport.handler = (call) => const MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.server,
          message: 'offer_exists',
          code: 'P0001',
        );
        await expectLater(
          backend.submitOffer(
            requestId: requestId,
            terms: terms(),
            operationKey: 'duplicate-key',
          ),
          throwsA(
            isA<StoreBackendException>()
                .having(
                  (error) => error.toString(),
                  'message',
                  contains('already sent an offer'),
                )
                .having((error) => error.ambiguous, 'ambiguous', isFalse),
          ),
        );
      },
    );

    for (final gate in {
      'weekly_target_limit': 'weekly targeting limit',
      'insufficient_single_batch': 'prepaid credits cannot cover',
    }.entries) {
      test('explains ${gate.key} without treating it as a pending offer', () async {
        transport.handler = (call) => MarketplaceTransportError(
          kind: MarketplaceTransportErrorKind.server, code: 'P0001', message: gate.key,
        );
        await expectLater(backend.submitOffer(requestId: requestId, terms: terms(), operationKey: 'blocked-offer'),
          throwsA(isA<StoreBackendException>()
            .having((error) => error.message, 'message', contains(gate.value))
            .having((error) => error.ambiguous, 'ambiguous', isFalse)),
        );
      });
    }

    test('maps a network failure to an ambiguous outcome', () async {
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.connectivity,
        retryable: true,
      );
      await expectLater(
        backend.submitOffer(
          requestId: requestId,
          terms: terms(),
          operationKey: 'offer-key',
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

  group('resolved schedule decoding', () {
    test('decodes occurrence, offset and instant from a revision', () {
      final decoded = decodeOfferJson(
        offerJson(
          revisionOverrides: <String, Object?>{
            'schedule_occurrence': 'earlier',
            'schedule_utc_offset_minutes': -240,
            'schedule_utc_instant': '2026-11-01T05:30:00+00:00',
          },
        ),
        'offer',
      );
      final revision = decoded.revisions.single;
      expect(
        revision.terms.schedule.occurrence,
        RepeatedTimeOccurrence.earlier,
      );
      expect(revision.resolvedUtcOffsetMinutes, -240);
      expect(revision.resolvedUtcInstant, DateTime.utc(2026, 11, 1, 5, 30));
    });
  });
}

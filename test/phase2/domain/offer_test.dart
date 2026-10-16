import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/domain/phase2/phase2.dart';

void main() {
  final schedule = LocalSchedule(
    date: LocalDate(year: 2026, month: 5, day: 20),
    startTime: LocalTime(hour: 15, minute: 0),
    timezoneId: 'America/New_York',
  );
  final place = MeetingPlace(
    choice: MeetupPlaceChoice.specificPlace,
    label: 'Cross County Mall',
    address: 'Private address',
    placeId: 'place-1',
  );

  OfferTerms fullTerms({Money? price}) {
    return OfferTerms(
      price: price ?? Money(minorUnits: 55000, currencyCode: 'USD'),
      message: 'Like-new device with original charger.',
      imageMediaIds: const ['media-1', 'media-2'],
      schedule: schedule,
      place: place,
    );
  }

  Offer offerWithTwoRevisions({String? acceptedRevisionId}) {
    return Offer(
      id: 'offer-1',
      requestId: 'request-1',
      buyerUserId: 'auth-buyer',
      sellerProfileId: 'seller-1',
      sellerUserId: 'auth-seller',
      status: OfferStatus.selected,
      acceptedRevisionId: acceptedRevisionId,
      stamp: RecordStamp(
        revision: 2,
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 2),
      ),
      revisions: [
        OfferRevision(
          id: 'rev-1',
          offerId: 'offer-1',
          sequence: 1,
          terms: fullTerms(
            price: Money(minorUnits: 60000, currencyCode: 'USD'),
          ),
          status: OfferRevisionStatus.superseded,
          proposedByUserId: 'auth-seller',
          createdAt: DateTime.utc(2026, 5, 1),
        ),
        OfferRevision(
          id: 'rev-2',
          offerId: 'offer-1',
          sequence: 2,
          terms: fullTerms(),
          status: OfferRevisionStatus.accepted,
          proposedByUserId: 'auth-seller',
          createdAt: DateTime.utc(2026, 5, 2),
        ),
      ],
    );
  }

  group('OfferTerms', () {
    test('carries every offer form field with money as minor units', () {
      final terms = fullTerms();

      expect(terms.price.minorUnits, 55000);
      expect(terms.price.currencyCode, 'USD');
      expect(terms.message, contains('original charger'));
      expect(terms.imageMediaIds, ['media-1', 'media-2']);
      expect(terms.schedule, schedule);
      expect(terms.place, place);
    });

    test('reports a non-positive price and an overlong message', () {
      final invalid = fullTerms(
        price: Money(minorUnits: 0, currencyCode: 'USD'),
      ).copyWith(message: 'x' * 1001);
      final issues = invalid.validationIssues();

      expect(
        issues.map((issue) => issue.field),
        containsAll(['price', 'message']),
      );
      expect(issues.first.code, ValidationCodes.invalidValue);
      expect(issues.last.code, ValidationCodes.tooLong);
    });

    test('copyWith preserves complete field values', () {
      final terms = fullTerms();
      final revised = terms.copyWith(message: 'Updated note.');

      expect(revised.message, 'Updated note.');
      expect(revised.price, terms.price);
      expect(revised.imageMediaIds, terms.imageMediaIds);
      expect(revised.schedule, terms.schedule);
      expect(revised.place, terms.place);
    });

    test('rejects blank image media ids', () {
      expect(
        () => OfferTerms(
          price: Money(minorUnits: 55000, currencyCode: 'USD'),
          imageMediaIds: const ['media-1', ' '],
          schedule: schedule,
          place: place,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Offer revisions', () {
    test('keeps the full revision history and resolves the accepted one', () {
      final offer = offerWithTwoRevisions(acceptedRevisionId: 'rev-2');

      expect(offer.revisions.length, 2);
      expect(offer.latestRevision.id, 'rev-2');
      expect(offer.acceptedRevision?.id, 'rev-2');
      expect(offer.revisions.first.status, OfferRevisionStatus.superseded);
      expect(offer.revisions.first.terms.price.minorUnits, 60000);
    });

    test('acceptedRevisionId must reference a revision of this offer', () {
      expect(
        () => offerWithTwoRevisions(acceptedRevisionId: 'rev-404'),
        throwsArgumentError,
      );
    });

    test('revisions must belong to the offer and ascend by sequence', () {
      expect(
        () => Offer(
          id: 'offer-1',
          requestId: 'request-1',
          buyerUserId: 'auth-buyer',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller',
          status: OfferStatus.submitted,
          stamp: RecordStamp(
            revision: 1,
            createdAt: DateTime.utc(2026, 5, 1),
            updatedAt: DateTime.utc(2026, 5, 1),
          ),
          revisions: [
            OfferRevision(
              id: 'rev-1',
              offerId: 'other-offer',
              sequence: 1,
              terms: fullTerms(),
              status: OfferRevisionStatus.proposed,
              proposedByUserId: 'auth-seller',
              createdAt: DateTime.utc(2026, 5, 1),
            ),
          ],
        ),
        throwsArgumentError,
      );

      expect(
        () => Offer(
          id: 'offer-1',
          requestId: 'request-1',
          buyerUserId: 'auth-buyer',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller',
          status: OfferStatus.submitted,
          stamp: RecordStamp(
            revision: 1,
            createdAt: DateTime.utc(2026, 5, 1),
            updatedAt: DateTime.utc(2026, 5, 1),
          ),
          revisions: [
            OfferRevision(
              id: 'rev-1',
              offerId: 'offer-1',
              sequence: 2,
              terms: fullTerms(),
              status: OfferRevisionStatus.proposed,
              proposedByUserId: 'auth-seller',
              createdAt: DateTime.utc(2026, 5, 1),
            ),
            OfferRevision(
              id: 'rev-2',
              offerId: 'offer-1',
              sequence: 1,
              terms: fullTerms(),
              status: OfferRevisionStatus.proposed,
              proposedByUserId: 'auth-seller',
              createdAt: DateTime.utc(2026, 5, 2),
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects an offer with no revisions', () {
      expect(
        () => Offer(
          id: 'offer-1',
          requestId: 'request-1',
          buyerUserId: 'auth-buyer',
          sellerProfileId: 'seller-1',
          sellerUserId: 'auth-seller',
          status: OfferStatus.submitted,
          stamp: RecordStamp(
            revision: 1,
            createdAt: DateTime.utc(2026, 5, 1),
            updatedAt: DateTime.utc(2026, 5, 1),
          ),
          revisions: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Multiple offers per request', () {
    test('two sellers keep separate offers linked to one request id', () {
      final first = offerWithTwoRevisions(acceptedRevisionId: 'rev-2');
      final second = Offer(
        id: 'offer-2',
        requestId: 'request-1',
        buyerUserId: 'auth-buyer',
        sellerProfileId: 'seller-2',
        sellerUserId: 'auth-seller-2',
        status: OfferStatus.submitted,
        stamp: RecordStamp(
          revision: 1,
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
        revisions: [
          OfferRevision(
            id: 'rev-3',
            offerId: 'offer-2',
            sequence: 1,
            terms: fullTerms(),
            status: OfferRevisionStatus.proposed,
            proposedByUserId: 'auth-seller-2',
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        ],
      );

      final offers = [first, second];
      expect(offers.where((offer) => offer.requestId == 'request-1').length, 2);
      expect(offers.map((offer) => offer.sellerProfileId).toSet(), {
        'seller-1',
        'seller-2',
      });
      expect(offers[1].acceptedRevision, isNull);
    });

    test('copyWith preserves the offer identity and revision history', () {
      final offer = offerWithTwoRevisions(acceptedRevisionId: 'rev-2');
      final updated = offer.copyWith(
        status: OfferStatus.completed,
        conversationId: 'conversation-1',
        stamp: RecordStamp(
          revision: 3,
          createdAt: offer.stamp.createdAt,
          updatedAt: DateTime.utc(2026, 5, 3),
        ),
      );

      expect(updated.id, offer.id);
      expect(updated.requestId, offer.requestId);
      expect(updated.sellerProfileId, offer.sellerProfileId);
      expect(updated.revisions, offer.revisions);
      expect(updated.acceptedRevisionId, 'rev-2');
      expect(updated.status, OfferStatus.completed);
      expect(updated.conversationId, 'conversation-1');
    });
  });

  group('Offer commands', () {
    test('carry complete terms, revisions and idempotency keys', () {
      final submit = SubmitOfferCommand(
        requestId: 'request-1',
        terms: fullTerms(),
        idempotencyKey: 'submit-1',
      );
      expect(submit.terms.price.minorUnits, 55000);

      final revise = ReviseOfferCommand(
        offerId: 'offer-1',
        expectedOfferRevision: 2,
        terms: fullTerms(),
        idempotencyKey: 'revise-1',
      );
      expect(revise.expectedOfferRevision, 2);

      final select = SelectOfferCommand(
        offerId: 'offer-1',
        revisionId: 'rev-2',
        expectedOfferRevision: 2,
        idempotencyKey: 'select-1',
      );
      expect(select.revisionId, 'rev-2');
      expect(select.expectedOfferRevision, 2);

      final withdraw = WithdrawOfferCommand(
        offerId: 'offer-1',
        expectedOfferRevision: 2,
        idempotencyKey: 'withdraw-1',
      );
      expect(withdraw.expectedOfferRevision, 2);
    });

    test('reject missing ids, blank keys and revisions below one', () {
      expect(
        () => SubmitOfferCommand(
          requestId: '',
          terms: fullTerms(),
          idempotencyKey: 'submit-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => SelectOfferCommand(
          offerId: 'offer-1',
          revisionId: 'rev-2',
          expectedOfferRevision: 0,
          idempotencyKey: 'select-1',
        ),
        throwsArgumentError,
      );
      expect(
        () => ReviseOfferCommand(
          offerId: 'offer-1',
          expectedOfferRevision: 2,
          terms: fullTerms(),
          idempotencyKey: ' ',
        ),
        throwsArgumentError,
      );
    });
  });
}

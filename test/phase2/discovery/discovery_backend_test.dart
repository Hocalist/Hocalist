// Discovery completion data-layer tests: paged leads, recommended leads,
// review retry identity, session replacement and origin-isolated enquiry.
//
// No SDK, network or plugin use.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/data/phase2/discovery/discovery_adapter.dart';
import 'package:hocalist/data/phase2/discovery/discovery_backends.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_adapter.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_leads_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/reviews/review_backend.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/domain/phase2/failures.dart';
import 'package:hocalist/domain/phase2/reviews.dart';

import '../marketplace/support/marketplace_fakes.dart';

Map<String, Object?> leadWithDiscoveryFields() => <String, Object?>{
  ...leadJson(),
  'distance_miles': 3.4,
  'match_percent': 80,
  'match_reasons': <Object?>['Matches your declared category'],
};

Map<String, Object?> leadEnvelope({
  String sort = 'recommended',
  String? cursor,
  List<Map<String, Object?>>? items,
}) => <String, Object?>{
  'items': items ?? [leadWithDiscoveryFields()],
  'next_cursor': cursor,
  'sort': sort,
  'applied_radius_miles': 50,
  'distance_available': true,
  'manual_area_fallback': false,
  'declared_category_count': 1,
};

Map<String, Object?> reviewJson({int revision = 1, String status = 'published'}) =>
    <String, Object?>{
      'id': '60000000-0000-4000-8000-000000000001',
      'request_id': requestId,
      'rating': 5,
      'body': 'Clear photos and fair price.',
      'status': status,
      'revision': revision,
      'created_at': '2026-05-01T00:00:00+00:00',
      'updated_at': '2026-05-01T00:01:00+00:00',
      'moderation_reason': null,
    };

void main() {
  group('paged seller discovery', () {
    test('propagates cursors, filters, sorts and match reasons', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = MarketplaceDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(sellerId),
      );
      final backend = Phase2MarketplaceLeadsBackend(
        adapter: adapter,
        sellerUserId: sellerId,
      );
      transport.handler = (call) => MarketplaceTransportData(
        leadEnvelope(cursor: 'recommended|50|1|123|uuid'),
      );
      final page = await backend.loadLeadPage(
        filter: DiscoveryLeadFilter(
          categoryId: categoryId,
          areaLabel: 'Yonkers',
          query: 'ipad',
          budgetMaximumMinor: 50000,
          sort: DiscoverySort.recommended,
          radiusMiles: 25,
        ),
        cursor: 'newest|123|uuid',
        limit: 20,
      );
      final call = transport.calls.single;
      expect(call.function, 'marketplace_discovery_leads');
      expect(call.params['p_cursor'], 'newest|123|uuid');
      expect(call.params['p_sort'], 'recommended');
      expect(call.params['p_area'], 'Yonkers');
      expect(call.params['p_query'], 'ipad');
      expect(call.params['p_budget_max_minor'], 50000);
      expect(call.params['p_radius_miles'], 25);
      expect(page.nextCursor, 'recommended|50|1|123|uuid');
      expect(page.sort, DiscoverySort.recommended);
      expect(page.items.single.distanceMiles, 3.4);
      expect(page.items.single.matchPercent, 80);
      expect(page.matchReasons.single, ['Matches your declared category']);
      // Server-authorized projection only: no exact location fields decode.
      expect(page.items.single.areaLabel, 'Yonkers, NY');
    });

    test('a malformed page fails closed without inventing items', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = MarketplaceDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(sellerId),
      );
      final backend = Phase2MarketplaceLeadsBackend(
        adapter: adapter,
        sellerUserId: sellerId,
      );
      transport.handler = (call) =>
          const MarketplaceTransportData(<String, Object?>{'items': 'nope'});
      await expectLater(
        backend.loadLeadPage(
          filter: DiscoveryLeadFilter(sort: DiscoverySort.newest),
        ),
        throwsA(isA<StoreBackendException>()),
      );
    });

    test('a replaced session cannot apply a stale page', () async {
      final transport = FakeMarketplaceTransport();
      final session = FakeMarketplaceSession(sellerId);
      final adapter = MarketplaceDataAdapter(
        transport: transport,
        session: session,
      );
      final backend = Phase2MarketplaceLeadsBackend(
        adapter: adapter,
        sellerUserId: sellerId,
      );
      final gate = Completer<void>();
      transport.gate = gate.future;
      transport.handler = (call) => MarketplaceTransportData(leadEnvelope());
      final pending = backend.loadLeadPage(
        filter: DiscoveryLeadFilter(sort: DiscoverySort.newest),
      );
      session.replaceWith(buyerId);
      gate.complete();
      await expectLater(pending, throwsA(isA<StoreBackendException>()));
      expect(session.currentUserId, buyerId);
    });
  });

  group('recommended leads', () {
    test('decodes the declared basis and honest empty reason', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = DiscoveryDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(sellerId),
      );
      final backend = Phase2DiscoveryBackend(
        adapter: adapter,
        identity: () => sellerId,
      );
      transport.handler = (call) => MarketplaceTransportData({
        'items': [leadWithDiscoveryFields()],
        'basis': {
          'declared_categories': [
            {'id': categoryId, 'label': 'Electronics'},
          ],
          'area_label': 'Yonkers, NY',
          'radius_miles': 25,
        },
        'unavailable_reason': null,
      });
      final view = await backend.loadRecommendedLeads();
      expect(view.items.single.matchPercent, 80);
      expect(view.basis.declaredCategoryLabels, ['Electronics']);
      expect(view.basis.radiusMiles, 25);
      expect(view.matchReasons.single, isNotEmpty);
      expect(view.hasBasis, isTrue);
      expect(transport.calls.single.function, 'marketplace_recommended_leads');
    });

    test('surfaces the server unavailable reason without fabricating rows', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = DiscoveryDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(sellerId),
      );
      final backend = Phase2DiscoveryBackend(
        adapter: adapter,
        identity: () => sellerId,
      );
      transport.handler = (call) => MarketplaceTransportData({
        'items': <Object?>[],
        'basis': {
          'declared_categories': <Object?>[],
          'area_label': null,
          'radius_miles': null,
        },
        'unavailable_reason': 'no_matching_basis',
      });
      final view = await backend.loadRecommendedLeads();
      expect(view.items, isEmpty);
      expect(view.hasBasis, isFalse);
      expect(view.unavailableReason, 'no_matching_basis');
    });
  });

  group('post-purchase reviews', () {
    test('submit retries with one intent key and never duplicates locally', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = ReviewDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      final backend = Phase2ReviewBackend(adapter: adapter);
      transport.handler = (call) => MarketplaceTransportData(reviewJson());
      final command = SubmitReviewCommand(
        requestId: requestId,
        rating: 5,
        body: 'Clear photos and fair price.',
        idempotencyKey: 'review-key-1',
      );
      final first = await backend.submitReview(command);
      expect(first.rating, 5);
      expect(first.revision, 1);
      expect(transport.calls.single.function, 'review_submit');
      expect(
        (transport.calls.single.params['p_input']! as Map)['request_id'],
        requestId,
      );
      // A retry of the same intent reuses the key.
      await backend.submitReview(command);
      expect(transport.calls.length, 2);
      expect(
        transport.calls[1].params['p_key'],
        transport.calls[0].params['p_key'],
      );
      expect(
        (transport.calls[1].params['p_input']! as Map)['rating'],
        5,
      );
    });

    test('an uncertain failure is reported as ambiguous for safe retry', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = ReviewDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      final backend = Phase2ReviewBackend(adapter: adapter);
      transport.handler = (call) => const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.connectivity,
        retryable: true,
      );
      await expectLater(
        backend.submitReview(
          SubmitReviewCommand(
            requestId: requestId,
            rating: 4,
            idempotencyKey: 'review-key-2',
          ),
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

    test('eligibility decodes the existing review and not_confirmed state', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = ReviewDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      transport.handler = (call) => MarketplaceTransportData({
        'request_id': requestId,
        'eligible': true,
        'reason': 'confirmed_purchase',
        'outcome_id': '70000000-0000-4000-8000-000000000001',
        'review': reviewJson(revision: 2, status: 'hidden'),
      });
      final result = await adapter.fetchEligibility(requestId);
      final view = result.valueOrNull!;
      expect(view.eligible, isTrue);
      expect(view.review!.revision, 2);
      expect(view.review!.status, ReviewModerationState.hidden);
      expect(view.review!.isPublished, isFalse);
      expect(result.isFailure, isFalse);
    });

    test('a stale session cannot return eligibility for a replaced user', () async {
      final transport = FakeMarketplaceTransport();
      final session = FakeMarketplaceSession(buyerId);
      final adapter = ReviewDataAdapter(transport: transport, session: session);
      final gate = Completer<void>();
      transport.gate = gate.future;
      transport.handler = (call) => MarketplaceTransportData({
        'request_id': requestId,
        'eligible': true,
        'reason': 'confirmed_purchase',
        'review': null,
      });
      final pending = adapter.fetchEligibility(requestId);
      session.replaceWith(sellerId);
      gate.complete();
      final result = await pending;
      expect(result.isFailure, isTrue);
      expect(result.errorOrNull!.kind, RepositoryFailureKind.permissionDenied);
    });

    test('reputation decodes published aggregate fields only', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = ReviewDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      transport.handler = (call) => MarketplaceTransportData({
        'seller_profile_id': sellerProfileId,
        'rating_sum': 9,
        'rating_count': 2,
        'completed_deals': 3,
        'reviews': [
          {
            'id': '60000000-0000-4000-8000-000000000002',
            'rating': 5,
            'body': 'Great meeting.',
            'reviewer_label': 'Hocalist buyer',
            'created_at': '2026-05-01T00:00:00+00:00',
          },
        ],
      });
      final result = await adapter.fetchReputation(sellerProfileId);
      final reputation = result.valueOrNull!;
      expect(reputation.averageRating, 4.5);
      expect(reputation.completedDeals, 3);
      expect(reputation.reviews.single.reviewerLabel, 'Hocalist buyer');
      expect(reputation.available, isTrue);
    });

    test('a withheld target reputation is surfaced as unavailable', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = ReviewDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      transport.handler = (call) => MarketplaceTransportData({
        'seller_profile_id': sellerProfileId,
        'available': false,
        'reason': 'target_unavailable',
        'rating_sum': 0,
        'rating_count': 0,
        'completed_deals': 0,
        'reviews': <Object?>[],
      });
      final result = await adapter.fetchReputation(sellerProfileId);
      final reputation = result.valueOrNull!;
      expect(reputation.available, isFalse);
      expect(reputation.withheldReason, 'target_unavailable');
      expect(reputation.ratingCount, 0);
      expect(reputation.reviews, isEmpty);
    });
  });

  group('discovery enquiries and consent', () {
    test('store enquiry sends only the origin and listing subject', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = DiscoveryDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      final backend = Phase2DiscoveryBackend(
        adapter: adapter,
        identity: () => buyerId,
      );
      transport.handler = (call) => MarketplaceTransportData({
        'conversation_id': '80000000-0000-4000-8000-000000000001',
        'origin': 'store_listing',
        'subject_id': listingId,
      });
      final opened = await backend.openEnquiry(
        origin: DiscoveryEnquiryOrigin.storeListing,
        subjectId: listingId,
        operationKey: 'enquiry-1',
      );
      expect(opened.origin, DiscoveryEnquiryOrigin.storeListing);
      expect(opened.subjectId, listingId);
      final input = transport.calls.single.params['p_input']! as Map;
      expect(input.keys.toSet(), {'origin', 'listing_id'});
      expect(input['origin'], 'store_listing');
    });

    test('hocatrends enquiry carries the topic and seller profile', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = DiscoveryDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      final backend = Phase2DiscoveryBackend(
        adapter: adapter,
        identity: () => buyerId,
      );
      transport.handler = (call) => MarketplaceTransportData({
        'conversation_id': '80000000-0000-4000-8000-000000000002',
        'origin': 'hocatrends_enquiry',
        'subject_id': categoryId,
      });
      await backend.openEnquiry(
        origin: DiscoveryEnquiryOrigin.hocatrendsEnquiry,
        subjectId: categoryId,
        sellerProfileId: sellerProfileId,
        operationKey: 'enquiry-2',
      );
      final input = transport.calls.single.params['p_input']! as Map;
      expect(input['topic_id'], categoryId);
      expect(input['seller_profile_id'], sellerProfileId);
      expect(input.containsKey('listing_id'), isFalse);
    });

    test('consent is closed by default and round-trips explicit flags', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = DiscoveryDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(buyerId),
      );
      final backend = Phase2DiscoveryBackend(
        adapter: adapter,
        identity: () => buyerId,
      );
      transport.handler = (call) => MarketplaceTransportData({
        'is_public': false,
        'show_display_name': false,
        'show_area': false,
        'show_categories': false,
        'revision': 0,
      });
      final consent = await backend.loadConsent();
      expect(consent.isPublic, isFalse);

      transport.handler = (call) => MarketplaceTransportData({
        'is_public': true,
        'show_display_name': true,
        'show_area': false,
        'show_categories': false,
        'revision': 1,
      });
      final updated = await backend.setConsent(
        consent: const BuyerPublicProfileConsent(
          isPublic: true,
          showDisplayName: true,
        ),
        operationKey: 'consent-1',
      );
      expect(updated.isPublic, isTrue);
      expect(updated.revision, 1);
      final input = transport.calls.last.params['p_input']! as Map;
      expect(input, {
        'is_public': true,
        'show_display_name': true,
        'show_area': false,
        'show_categories': false,
      });
    });

    test('an unauthenticated session cannot open an enquiry', () async {
      final transport = FakeMarketplaceTransport();
      final adapter = DiscoveryDataAdapter(
        transport: transport,
        session: FakeMarketplaceSession(null),
      );
      final result = await adapter.openEnquiry(
        origin: DiscoveryEnquiryOrigin.storeListing,
        subjectId: listingId,
        operationKey: 'enquiry-3',
      );
      expect(result.isFailure, isTrue);
      expect(transport.calls, isEmpty);
    });
  });
}

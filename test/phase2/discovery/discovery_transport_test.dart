// Real-SDK transport coverage for the discovery_completion RPCs.
//
// Uses the real Supabase SDK over a synthetic HTTP backend: schema
// restriction, signed-out refusal, pinned-token behavior, response decoding,
// and identity replacement are exercised through the composition entry points
// rather than fake adapters.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hocalist/data/phase2/discovery/discovery_adapter.dart';
import 'package:hocalist/data/phase2/discovery/discovery_composition.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_composition.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_leads_backend.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';
import 'package:hocalist/data/phase2/marketplace/supabase_marketplace_transport.dart';
import 'package:hocalist/data/phase2/reviews/review_composition.dart';
import 'package:hocalist/data/local_marketplace_repository.dart';
import 'package:hocalist/domain/phase2/discovery.dart';
import 'package:hocalist/domain/phase2/reviews.dart';

import '../accounts/support/supabase_http_backend.dart';
import '../marketplace/support/marketplace_fakes.dart';

Map<String, Object?> _lead() => <String, Object?>{
  ...leadJson(),
  'distance_miles': 3.4,
  'match_percent': 80,
  'match_reasons': <Object?>['Matches your declared category'],
};

Map<String, Object?> _review({int revision = 1}) => <String, Object?>{
  'id': '60000000-0000-4000-8000-000000000001',
  'request_id': requestId,
  'rating': 5,
  'body': 'Clear photos and fair price.',
  'status': 'published',
  'revision': revision,
  'created_at': '2026-05-01T00:00:00+00:00',
  'updated_at': '2026-05-01T00:01:00+00:00',
  'moderation_reason': null,
};

Map<String, Object?> _payload(String function) => switch (function) {
  'discovery_origin_json' || 'discovery_origin_set' => <String, Object?>{
    'configured': true,
    'area_label': 'Yonkers, NY',
    'coordinates_present': true,
    'radius_miles': 25,
    'revision': 1,
  },
  'marketplace_discovery_leads' => <String, Object?>{
    'items': [_lead()],
    'next_cursor': 'newest|123|uuid',
    'sort': 'newest',
    'applied_radius_miles': 25,
    'distance_available': true,
    'manual_area_fallback': false,
    'declared_category_count': 1,
  },
  'marketplace_recommended_leads' => <String, Object?>{
    'items': [_lead()],
    'basis': <String, Object?>{
      'declared_categories': [
        <String, Object?>{'id': categoryId, 'label': 'Electronics'},
      ],
      'area_label': 'Yonkers, NY',
      'radius_miles': 25,
    },
    'unavailable_reason': null,
  },
  'marketplace_seller_outcomes' => <String, Object?>{
    'items': [
      <String, Object?>{
        'outcome_id': '70000000-0000-4000-8000-000000000001',
        'meeting_id': '72000000-0000-4000-8000-000000000001',
        'request_id': requestId,
        'offer_id': offerId,
        'confirmed_at': '2026-05-01T00:00:00+00:00',
      },
    ],
  },
  'review_status' => <String, Object?>{
    'request_id': requestId,
    'eligible': true,
    'reason': 'confirmed_purchase',
    'outcome_id': '70000000-0000-4000-8000-000000000001',
    'review': null,
  },
  'review_submit' || 'review_update' => _review(),
  'seller_public_reputation' => <String, Object?>{
    'seller_profile_id': sellerProfileId,
    'rating_sum': 9,
    'rating_count': 2,
    'completed_deals': 3,
    'reviews': [
      <String, Object?>{
        'id': '60000000-0000-4000-8000-000000000002',
        'rating': 5,
        'body': 'Great meeting.',
        'reviewer_label': 'Hocalist buyer',
        'created_at': '2026-05-01T00:00:00+00:00',
      },
    ],
  },
  'buyer_public_profile_consent_json' ||
  'buyer_public_profile_consent_set' => <String, Object?>{
    'is_public': true,
    'show_display_name': true,
    'show_area': false,
    'show_categories': false,
    'revision': 1,
  },
  'buyer_public_profile' => <String, Object?>{
    'available': true,
    'profile_id': buyerProfileId,
    'role': 'buyer',
    'display_name': 'Buyer A',
    'area_label': null,
    'categories': <Object?>[],
    'member_since': '2026-05-01T00:00:00+00:00',
    'verified_purchase_count': 1,
  },
  'hocatrends_trends' => <String, Object?>{
    'window_days': 30,
    'generated_at': '2026-05-01T00:00:00+00:00',
    'open_request_total': 1,
    'items': [
      <String, Object?>{
        'rank': 1,
        'category_id': categoryId,
        'label': 'Electronics',
        'open_requests': 1,
        'competing_sellers': 1,
        'confirmed_purchases': 1,
        'participating_buyers': 1,
        'percent': 100,
        'competition': 'Medium',
        'activity_copy': '1 seller competing · 1 confirmed purchase',
        'verified_activity': true,
      },
    ],
  },
  'hocatrends_winners' => <String, Object?>{
    'window_days': 30,
    'generated_at': '2026-05-01T00:00:00+00:00',
    'items': [
      <String, Object?>{
        'outcome_id': '70000000-0000-4000-8000-000000000001',
        'category_label': 'Electronics',
        'buyer_label': 'Hocalist buyer',
        'area_label': null,
        'confirmed_at': '2026-05-01T00:00:00+00:00',
        'verified_purchase': true,
      },
    ],
  },
  'hocatrends_topic_sellers' => <String, Object?>{
    'topic_id': categoryId,
    'items': [
      <String, Object?>{
        'seller_profile_id': sellerProfileId,
        'seller_user_id': sellerId,
        'display_name': 'Seller B',
        'area_label': 'Yonkers, NY',
        'listing_id': listingId,
        'listing_title': 'Deep clean',
        'price_label': r'From $80',
        'rating_sum': 0,
        'rating_count': 0,
        'completed_deals': 1,
      },
    ],
  },
  'discovery_open_enquiry' => <String, Object?>{
    'conversation_id': '80000000-0000-4000-8000-000000000001',
    'origin': 'store_listing',
    'subject_id': listingId,
  },
  _ => const <String, Object?>{},
};

void main() {
  test(
    'every discovery/review composition path reaches the real SDK transport',
    () async {
      final auth = SyntheticAccountBackend().client();
      final requests = <http.Request>[];
      final client = buildSyntheticSupabaseClient(
        MockClient((request) async {
          if (request.url.path.startsWith('/auth/')) {
            final forwarded = http.Request(request.method, request.url)
              ..headers.addAll(request.headers)
              ..bodyBytes = request.bodyBytes;
            return http.Response.fromStream(await auth.send(forwarded));
          }
          requests.add(request);
          final name = request.url.pathSegments.isEmpty
              ? ''
              : request.url.pathSegments.last;
          return http.Response(
            jsonEncode(_payload(name)),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'user-a@example.com',
        password: 'synthetic',
      );

      final discovery = createConfiguredDiscoveryBackend(
        enabled: true,
        client: client,
      );
      final reviews = createConfiguredReviewBackend(
        enabled: true,
        client: client,
      );
      expect(discovery, isNotNull);
      expect(reviews, isNotNull);

      final calls = <(String, Future<Object?> Function())>[
        (
          'marketplace_recommended_leads',
          () => discovery!.loadRecommendedLeads(),
        ),
        ('hocatrends_trends', () => discovery!.loadTrends()),
        ('hocatrends_winners', () => discovery!.loadWinners()),
        (
          'hocatrends_topic_sellers',
          () => discovery!.loadTopicSellers(categoryId),
        ),
        (
          'marketplace_seller_outcomes',
          () => discovery!.loadConfirmedMeetingIds(),
        ),
        ('discovery_origin_json', () => discovery!.loadOrigin()),
        (
          'discovery_origin_set',
          () => discovery!.setOrigin(
            input: const SellerDiscoveryOriginInput(areaLabel: 'Yonkers, NY'),
            operationKey: 'origin-1',
          ),
        ),
        (
          'buyer_public_profile_consent_json',
          () => discovery!.loadConsent(),
        ),
        (
          'buyer_public_profile_consent_set',
          () => discovery!.setConsent(
            consent: const BuyerPublicProfileConsent(
              isPublic: true,
              showDisplayName: true,
            ),
            operationKey: 'consent-1',
          ),
        ),
        (
          'buyer_public_profile',
          () => discovery!.loadPublicProfile(buyerProfileId),
        ),
        (
          'discovery_open_enquiry',
          () => discovery!.openEnquiry(
            origin: DiscoveryEnquiryOrigin.storeListing,
            subjectId: listingId,
            operationKey: 'enquiry-1',
          ),
        ),
        ('review_status', () => reviews!.loadEligibility(requestId)),
        (
          'review_submit',
          () => reviews!.submitReview(
            SubmitReviewCommand(
              requestId: requestId,
              rating: 5,
              idempotencyKey: 'review-1',
            ),
          ),
        ),
        (
          'review_update',
          () => reviews!.updateReview(
            UpdateReviewCommand(
              reviewId: '60000000-0000-4000-8000-000000000001',
              expectedRevision: 1,
              rating: 4,
              idempotencyKey: 'review-2',
            ),
          ),
        ),
        (
          'seller_public_reputation',
          () => reviews!.loadReputation(sellerProfileId),
        ),
      ];

      for (final (function, call) in calls) {
        final before = requests.length;
        final result = await call();
        expect(result, isNotNull, reason: function);
        expect(requests.length, before + 1, reason: function);
        final request = requests.last;
        expect(request.url.path, '/rest/v1/rpc/$function', reason: function);
        expect(request.headers['Content-Profile'], 'hocalist', reason: function);
        expect(
          request.headers['Authorization'],
          'Bearer ${client.auth.currentSession!.accessToken}',
          reason: function,
        );
      }

      // Paged leads use the marketplace adapter transport with the same
      // allowlist and cursor propagation.
      final leads = Phase2MarketplaceLeadsBackend(
        adapter: createMarketplaceDataAdapter(client: client),
        sellerUserId: syntheticUserA,
      );
      final page = await leads.loadLeadPage(
        filter: DiscoveryLeadFilter(sort: DiscoverySort.newest),
      );
      expect(requests.last.url.path, '/rest/v1/rpc/marketplace_discovery_leads');
      expect(page.items.single.matchPercent, 80);
      expect(page.matchReasons.single, ['Matches your declared category']);
      expect(page.nextCursor, 'newest|123|uuid');

      // Internal and admin-only functions are refused before dispatch even
      // though they exist in the SQL bundle.
      final transport = SupabaseMarketplaceTransport(client);
      final count = requests.length;
      for (final internal in [
        'discovery_lead_json',
        'discovery_distance_miles',
        'discovery_declared_category_ids',
        'review_json',
        'review_reviewer_label',
        'review_moderate',
      ]) {
        await expectLater(
          transport.callMarketplaceRpc(
            MarketplaceRpcCall(
              schema: 'hocalist',
              function: internal,
              params: const {},
            ),
          ),
          throwsUnsupportedError,
          reason: internal,
        );
      }
      expect(requests.length, count);

      // Signed-out calls are refused before dispatch.
      await client.auth.signOut();
      await transport.callMarketplaceRpc(
        MarketplaceRpcCall(
          schema: 'hocalist',
          function: 'review_status',
          params: const {'p_request': requestId},
        ),
      );
      expect(requests.length, count);

      // A non-hocalist schema is refused.
      await expectLater(
        transport.callMarketplaceRpc(
          MarketplaceRpcCall(
            schema: 'public',
            function: 'marketplace_command',
            params: const {},
          ),
        ),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'an in-flight call pins its token and fences a replaced identity',
    () async {
      final auth = SyntheticAccountBackend().client();
      final requests = <http.Request>[];
      final requestSeen = Completer<void>();
      final gate = Completer<void>();
      final client = buildSyntheticSupabaseClient(
        MockClient((request) async {
          if (request.url.path.startsWith('/auth/')) {
            final forwarded = http.Request(request.method, request.url)
              ..headers.addAll(request.headers)
              ..bodyBytes = request.bodyBytes;
            return http.Response.fromStream(await auth.send(forwarded));
          }
          requests.add(request);
          if (!requestSeen.isCompleted) requestSeen.complete();
          await gate.future;
          return http.Response(
            jsonEncode(_payload('marketplace_recommended_leads')),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'user-a@example.com',
        password: 'synthetic',
      );
      final tokenA = client.auth.currentSession!.accessToken;
      final discovery = createConfiguredDiscoveryBackend(
        enabled: true,
        client: client,
      )!;
      final pending = discovery.loadRecommendedLeads();
      await requestSeen.future;
      await client.auth.signOut();
      await client.auth.signInWithPassword(
        email: 'user-b@example.com',
        password: 'synthetic',
      );
      gate.complete();
      await expectLater(pending, throwsA(isA<StoreBackendException>()));
      expect(requests.single.headers['Authorization'], 'Bearer $tokenA');
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/marketplace_recommended_leads',
      );
    },
  );
}


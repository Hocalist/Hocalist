// Shared fakes for the marketplace data-layer tests. No SDK, network or
// plugin use.
import 'dart:async';

import 'package:hocalist/data/phase2/marketplace/marketplace_session.dart';
import 'package:hocalist/data/phase2/marketplace/marketplace_transport.dart';

class FakeMarketplaceSession implements MarketplaceSession {
  FakeMarketplaceSession(this.currentUserId);

  @override
  String? currentUserId;

  void replaceWith(String? userId) => currentUserId = userId;
}

class FakeMarketplaceTransport implements MarketplaceTransport {
  final List<MarketplaceRpcCall> calls = <MarketplaceRpcCall>[];
  MarketplaceTransportResponse Function(MarketplaceRpcCall call)? handler;
  Future<void>? gate;

  @override
  Future<MarketplaceTransportResponse> callMarketplaceRpc(
    MarketplaceRpcCall call,
  ) async {
    calls.add(call);
    final gate = this.gate;
    if (gate != null) await gate;
    final handler = this.handler;
    if (handler != null) return handler(call);
    return const MarketplaceTransportData(<String, Object?>{});
  }
}

const String categoryId = '20000000-0000-4000-8000-000000000001';
const String requestId = '30000000-0000-4000-8000-000000000001';
const String offerId = '40000000-0000-4000-8000-000000000001';
const String revisionId = '41000000-0000-4000-8000-000000000001';
const String listingId = '50000000-0000-4000-8000-000000000001';
const String buyerId = 'user-a';
const String sellerId = 'user-b';
const String buyerProfileId = '10000000-0000-4000-8000-00000000000a';
const String sellerProfileId = '10000000-0000-4000-8000-00000000000b';

Map<String, Object?> budgetJson({
  int? minimum = 35000,
  int? maximum = 48000,
  String? currency = 'USD',
}) => <String, Object?>{
  'minimum_minor': minimum,
  'maximum_minor': maximum,
  'currency': currency,
};

Map<String, Object?> requestJson({
  String id = requestId,
  String status = 'active',
  int revision = 1,
  String kind = 'product',
  String? condition = 'used',
  String? serviceType,
  bool useHomeAddress = true,
  String? addressLine1,
}) => <String, Object?>{
  'id': id,
  'buyer_user_id': buyerId,
  'buyer_profile_id': buyerProfileId,
  'kind': kind,
  'title': 'iPad Air, 5th gen or newer',
  'description': 'Needs to be in good condition.',
  'condition': condition,
  'service_type': serviceType,
  'quantity': 1,
  'budget': budgetJson(),
  'accepts_higher_offers': false,
  'category_id': categoryId,
  'location': <String, Object?>{
    'use_home_address': useHomeAddress,
    'address_line1': addressLine1,
    'address_line2': null,
    'city': useHomeAddress ? null : 'Yonkers',
    'region': null,
    'postal_code': null,
    'country_code': null,
  },
  'status': status,
  'revision': revision,
  'created_at': '2026-05-01T00:00:00+00:00',
  'updated_at': '2026-05-01T00:01:00+00:00',
};

Map<String, Object?> leadJson({
  int requestRevision = 1,
  String? areaLabel = 'Yonkers, NY',
}) => <String, Object?>{
  'request_id': requestId,
  'kind': 'product',
  'title': 'iPad Air, 5th gen or newer',
  'description': 'Needs to be in good condition.',
  'condition': 'used',
  'service_type': null,
  'quantity': 1,
  'budget': budgetJson(),
  'accepts_higher_offers': false,
  'category_id': categoryId,
  'buyer_profile_id': buyerProfileId,
  'buyer_display_name': 'Buyer A',
  'area_label': areaLabel,
  'request_revision': requestRevision,
  'published_at': '2026-05-01T00:00:00+00:00',
};

Map<String, Object?> revisionJson({
  int sequence = 1,
  String status = 'proposed',
  int priceMinor = 42000,
  Map<String, Object?> overrides = const <String, Object?>{},
}) => <String, Object?>{
  'id': revisionId,
  'offer_id': offerId,
  'sequence': sequence,
  'price_minor': priceMinor,
  'currency_code': 'USD',
  'message': 'Can meet tomorrow.',
  'image_media_ids': <Object?>[],
  'schedule_date': '2026-10-01',
  'schedule_time': '18:30',
  'schedule_timezone': 'America/New_York',
  'schedule_occurrence': null,
  'schedule_utc_offset_minutes': -240,
  'schedule_utc_instant': '2026-10-01T22:30:00+00:00',
  'place_choice': 'specific_place',
  'place_label': 'Cross County Mall',
  'place_address': '123 Synthetic Ave',
  'place_id': null,
  'status': status,
  'proposed_by_user_id': sellerId,
  'created_at': '2026-05-01T00:02:00+00:00',
  ...overrides,
};

Map<String, Object?> offerJson({
  String status = 'submitted',
  int revision = 1,
  String? acceptedRevisionId,
  String? conversationId,
  bool purchaseSelected = false,
  DateTime? requestAcceptanceExpiresAt,
  List<Map<String, Object?>>? revisions,
  Map<String, Object?> revisionOverrides = const <String, Object?>{},
}) => <String, Object?>{
  'id': offerId,
  'request_id': requestId,
  'buyer_user_id': buyerId,
  'seller_user_id': sellerId,
  'seller_profile_id': sellerProfileId,
  'seller_display_name': 'Seller B',
  'status': status,
  'accepted_revision_id': acceptedRevisionId,
  'conversation_id': conversationId,
  'purchase_selected': purchaseSelected,
  'request_first_accepted_at': requestAcceptanceExpiresAt == null
      ? null
      : '2026-05-01T00:00:00+00:00',
  'request_acceptance_expires_at': requestAcceptanceExpiresAt
      ?.toUtc()
      .toIso8601String(),
  'revision': revision,
  'created_at': '2026-05-01T00:02:00+00:00',
  'updated_at': '2026-05-01T00:02:30+00:00',
  'revisions': revisions ?? [revisionJson(overrides: revisionOverrides)],
};

Map<String, Object?> listingJson({
  String status = 'draft',
  String moderationStatus = 'pending_review',
  int revision = 1,
}) => <String, Object?>{
  'id': listingId,
  'seller_profile_id': sellerProfileId,
  'seller_user_id': sellerId,
  'kind': 'product',
  'title': 'iPad Air 5th Gen 64GB',
  'description': 'Excellent condition with charger included.',
  'category_id': categoryId,
  'category_label': 'Electronics',
  'price_label': r'$650',
  'service_area': 'Yonkers, NY',
  'availability': 'Available today',
  'image_media_ids': <Object?>[],
  'status': status,
  'moderation_status': moderationStatus,
  'revision': revision,
  'published_at': null,
  'created_at': '2026-05-01T00:03:00+00:00',
  'updated_at': '2026-05-01T00:03:30+00:00',
};

Map<String, Object?> publicListingJson() => <String, Object?>{
  'id': listingId,
  'seller_profile_id': sellerProfileId,
  'kind': 'product',
  'title': 'iPad Air 5th Gen 64GB',
  'description': 'Excellent condition with charger included.',
  'category_id': categoryId,
  'category_label': 'Electronics',
  'price_label': r'$650',
  'service_area': 'Yonkers, NY',
  'availability': 'Available today',
  'image_media_ids': <Object?>[],
  'published_at': '2026-05-01T00:03:00+00:00',
};

Map<String, Object?> catalogueJson() => <String, Object?>{
  'categories': [
    <String, Object?>{
      'id': categoryId,
      'parent_id': null,
      'label': 'Electronics',
      'slug': 'electronics',
      'scope': 'product',
      'status': 'active',
      'sort_order': 1,
      'revision': 1,
      'created_at': '2026-05-01T00:00:00+00:00',
      'updated_at': '2026-05-01T00:00:00+00:00',
      'groups': [
        <String, Object?>{
          'id': '21000000-0000-4000-8000-000000000001',
          'category_id': categoryId,
          'label': 'Condition',
          'selection_mode': 'single',
          'is_required': true,
          'status': 'active',
          'sort_order': 1,
          'revision': 1,
          'created_at': '2026-05-01T00:00:00+00:00',
          'updated_at': '2026-05-01T00:00:00+00:00',
          'options': [
            <String, Object?>{
              'id': '22000000-0000-4000-8000-000000000001',
              'group_id': '21000000-0000-4000-8000-000000000001',
              'label': 'Like new',
              'status': 'active',
              'sort_order': 1,
              'revision': 1,
              'created_at': '2026-05-01T00:00:00+00:00',
              'updated_at': '2026-05-01T00:00:00+00:00',
            },
          ],
        },
      ],
    },
  ],
};

Map<String, Object?> pageJson(
  List<Map<String, Object?>> items, {
  String? cursor,
}) => <String, Object?>{'items': items, 'next_cursor': cursor};

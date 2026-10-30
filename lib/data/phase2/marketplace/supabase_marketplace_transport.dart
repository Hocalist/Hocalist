/// Concrete marketplace transport over the official Supabase Flutter SDK.
///
/// RPC-only, restricted to the `hocalist` schema and the reviewed marketplace
/// functions. The captured access token is pinned on each request so a queued
/// call can never be sent with a replacement identity's token. Signed-out
/// calls return an `unauthorized` result before any HTTP request. There is no
/// service-role or API-key pathway.
library;

import 'dart:async';

import '../accounts/fresh_session_token.dart';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'marketplace_transport.dart';

class SupabaseMarketplaceTransport implements MarketplaceTransport {
  SupabaseMarketplaceTransport(this._client);

  static const String schema = 'hocalist';
  static const Set<String> allowedFunctions = {
    'sale_pin',
    'sale_history',
    'call_command',
    'call_status',
    'credit_wallet',
    'reward_wallet',
    'support_reasons',
    'support_list',
    'support_command',
    'marketplace_catalogue',
    'marketplace_locations',
    'marketplace_timezones',
    'meeting_list',
    'meeting_detail',
    'meeting_propose',
    'meeting_respond',
    'meeting_reschedule_propose',
    'meeting_cancel',
    'notification_inbox',
    'notification_mark_read',
    'notification_mark_all_read',
    'notification_preferences',
    'notification_preferences_update',
    'marketplace_request',
    'marketplace_my_requests',
    'marketplace_seller_leads',
    'marketplace_request_offers',
    'marketplace_my_offers',
    'marketplace_offer',
    'chat_deals',
    'marketplace_store_summary',
    'marketplace_my_store_listings',
    'marketplace_store_listing',
    'marketplace_public_store_listings',
    'marketplace_saved_items',
    'marketplace_saved_set',
    'marketplace_command',
    'marketplace_admin_command',
    'marketplace_admin_moderation_queue',
    'withdrawal_status',
    'withdrawal_request',
    'credit_deposit_status',
    'verification_submit',
    'verification_status',
    'account_health_status',
    'restriction_appeal_submit',
    // discovery_completion client-callable RPCs (package 02). Internal
    // helpers (discovery_lead_json, discovery_distance_miles,
    // discovery_declared_category_ids, review_json, review_reviewer_label) and
    // the admin-only review_moderate are deliberately absent.
    'discovery_origin_json',
    'discovery_origin_set',
    'marketplace_discovery_leads',
    'marketplace_recommended_leads',
    'marketplace_seller_outcomes',
    'review_status',
    'review_submit',
    'review_update',
    'seller_public_reputation',
    'buyer_public_profile_consent_json',
    'buyer_public_profile_consent_set',
    'buyer_public_profile',
    'hocatrends_trends',
    'hocatrends_winners',
    'hocatrends_topic_sellers',
    'discovery_open_enquiry',
  };

  final SupabaseClient _client;

  @override
  Future<MarketplaceTransportResponse> callMarketplaceRpc(
    MarketplaceRpcCall call,
  ) async {
    if (call.schema != schema) {
      throw UnsupportedError('Unsupported marketplace schema');
    }
    if (!allowedFunctions.contains(call.function)) {
      throw UnsupportedError('Unsupported marketplace function');
    }
    try {
      final token = await freshSessionToken(_client);
      if (token == null) return _unauthorized;
      final data = await _client
          .schema(schema)
          .rpc(call.function, params: call.params)
          .setHeader('Authorization', 'Bearer $token');
      return MarketplaceTransportData(data);
    } on PostgrestException catch (error) {
      return _fromPostgrest(error);
    } on AuthRetryableFetchException {
      return _connectivity;
    } on AuthException {
      return _unauthorized;
    } on TimeoutException {
      return _connectivity;
    } on http.ClientException {
      return _connectivity;
    } on Exception {
      return const MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.server,
      );
    }
  }

  MarketplaceTransportError _fromPostgrest(PostgrestException error) {
    final code = error.code;
    final parsedCode = int.tryParse(code ?? '');
    final statusCode =
        parsedCode != null && parsedCode >= 100 && parsedCode <= 599
        ? parsedCode
        : null;
    final unauthorized =
        code == 'PGRST301' ||
        code == 'PGRST302' ||
        code == 'PGRST303' ||
        statusCode == 401;
    return MarketplaceTransportError(
      kind: unauthorized
          ? MarketplaceTransportErrorKind.unauthorized
          : MarketplaceTransportErrorKind.server,
      code: code,
      message: error.message,
      statusCode: statusCode,
      retryable: statusCode != null && statusCode >= 500,
    );
  }

  static const MarketplaceTransportResponse _unauthorized =
      MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.unauthorized,
      );

  static const MarketplaceTransportResponse _connectivity =
      MarketplaceTransportError(
        kind: MarketplaceTransportErrorKind.connectivity,
        retryable: true,
      );
}

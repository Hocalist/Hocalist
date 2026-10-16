/// Composition entry point for the post-purchase review backend.
///
/// Enable only after the reviewed discovery_completion rollout (142) is
/// deployed and reviewed; the production composition keeps this false.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../marketplace/supabase_marketplace_session.dart';
import '../marketplace/supabase_marketplace_transport.dart';
import 'review_backend.dart';

/// Set true only after the reviewed review migration is deployed.
const bool kPostPurchaseReviewsEnabled = bool.fromEnvironment('HOCALIST_POST_PURCHASE_REVIEWS');

Phase2ReviewBackend? createConfiguredReviewBackend({
  bool enabled = kPostPurchaseReviewsEnabled,
  SupabaseClient? client,
}) {
  if (!enabled) return null;
  try {
    final resolved = client ?? Supabase.instance.client;
    return Phase2ReviewBackend(
      adapter: ReviewDataAdapter(
        transport: SupabaseMarketplaceTransport(resolved),
        session: SupabaseMarketplaceSession(resolved),
      ),
    );
  } catch (_) {
    return null;
  }
}

/// Live SDK session boundary for the marketplace data layer.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'marketplace_session.dart';

class SupabaseMarketplaceSession implements MarketplaceSession {
  const SupabaseMarketplaceSession(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentUser?.id;
}

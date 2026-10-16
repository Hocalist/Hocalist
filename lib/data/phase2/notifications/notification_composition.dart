/// Composition for the notification inbox data layer.
///
/// Returns null in prototype mode or before Supabase initialization so the
/// notification screens keep their local fixtures.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../local_marketplace_repository.dart';
import '../marketplace/marketplace_composition.dart';
import 'notification_adapter.dart';
import 'phase2_notifications_backend.dart';

NotificationDataAdapter createNotificationDataAdapter({
  required SupabaseClient client,
}) {
  final marketplace = createMarketplaceDataAdapter(client: client);
  return NotificationDataAdapter(
    transport: marketplace.transport,
    session: marketplace.session,
    errorMapper: marketplace.errorMapper,
  );
}

/// Notification backend when a real Supabase session is configured.
MarketplaceNotificationsBackend?
createConfiguredMarketplaceNotificationsBackend() {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceNotificationsBackend(
      adapter: createNotificationDataAdapter(client: client),
    );
  } catch (_) {
    return null;
  }
}

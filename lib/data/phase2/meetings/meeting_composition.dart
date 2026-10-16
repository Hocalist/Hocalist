/// Composition for the meeting/reschedule data layer.
///
/// Returns null in prototype mode or before Supabase initialization so the
/// meeting screens keep their local fixtures.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../local_marketplace_repository.dart';
import '../marketplace/marketplace_composition.dart';
import 'meeting_adapter.dart';
import 'phase2_meetings_backend.dart';

MeetingDataAdapter createMeetingDataAdapter({required SupabaseClient client}) {
  final marketplace = createMarketplaceDataAdapter(client: client);
  return MeetingDataAdapter(
    transport: marketplace.transport,
    session: marketplace.session,
    errorMapper: marketplace.errorMapper,
  );
}

/// Meeting backend when a real Supabase session is configured.
MarketplaceMeetingsBackend? createConfiguredMarketplaceMeetingsBackend() {
  try {
    final client = Supabase.instance.client;
    return Phase2MarketplaceMeetingsBackend(
      adapter: createMeetingDataAdapter(client: client),
    );
  } catch (_) {
    return null;
  }
}

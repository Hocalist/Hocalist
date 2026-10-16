/// Composition entry points for the discovery_completion package.
///
/// Enable only after `database/discovery_completion/rollout` is deployed and
/// reviewed. Tests and isolated previews inject an enabled capability; the
/// production composition keeps this false so an undeployed schema can never
/// make the app look connected.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../marketplace/supabase_marketplace_session.dart';
import '../marketplace/supabase_marketplace_transport.dart';
import 'discovery_adapter.dart';
import 'discovery_backends.dart';

/// Set true only after the reviewed discovery_completion rollout is deployed.
const bool kDiscoveryCompletionEnabled = bool.fromEnvironment('HOCALIST_DISCOVERY');

DiscoveryDataAdapter? createConfiguredDiscoveryAdapter({
  bool enabled = kDiscoveryCompletionEnabled,
  SupabaseClient? client,
}) {
  if (!enabled) return null;
  try {
    final resolved = client ?? Supabase.instance.client;
    return DiscoveryDataAdapter(
      transport: SupabaseMarketplaceTransport(resolved),
      session: SupabaseMarketplaceSession(resolved),
    );
  } catch (_) {
    return null;
  }
}

Phase2DiscoveryBackend? createConfiguredDiscoveryBackend({
  bool enabled = kDiscoveryCompletionEnabled,
  SupabaseClient? client,
}) {
  final adapter = createConfiguredDiscoveryAdapter(
    enabled: enabled,
    client: client,
  );
  if (adapter == null) return null;
  return Phase2DiscoveryBackend(
    adapter: adapter,
    identity: () => adapter.session.currentUserId,
  );
}

/// Composition for the app-side Places boundary.
///
/// Returns null in prototype mode or before Supabase initialization so place
/// capture keeps its manual fallback. The Google server credential stays in
/// the Edge Function secrets and is never read here.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'places_repository.dart';
import 'supabase_places_transport.dart';

/// Places repository when a real Supabase session is configured.
PlacesRepository? createConfiguredPlacesRepository() {
  try {
    final client = Supabase.instance.client;
    return PlacesRepository(transport: SupabasePlacesTransport(client));
  } catch (_) {
    return null;
  }
}

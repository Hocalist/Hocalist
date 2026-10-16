/// Validated Places reads for the app.
///
/// The repository checks the transport response against the shared contract
/// and maps anything unexpected to [PlacesFailureCode.invalidResponse]. It
/// keeps no query or address history and performs no automatic retries.
library;

import 'places_contract.dart';
import 'places_transport.dart';

class PlacesRepository {
  PlacesRepository({required this.transport});

  final PlacesTransport transport;

  /// Autocomplete suggestions for [input]. Blank or oversized input is
  /// rejected before any provider call.
  Future<List<PlaceSuggestion>> search({
    required String input,
    required PlacesSession session,
  }) async {
    final query = input.trim();
    if (query.isEmpty) return const <PlaceSuggestion>[];
    if (query.length > placesMaxQueryLength) {
      throw const PlacesFailure(PlacesFailureCode.invalidInput);
    }
    final result = await transport.autocomplete(
      input: query,
      sessionToken: session.token,
    );
    final suggestions = result.data['suggestions'];
    if (suggestions is! List || suggestions.length > 5) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    return suggestions.map(_suggestion).toList(growable: false);
  }

  /// Resolves one selected suggestion. A details call is only meaningful for a
  /// suggestion the user chose; callers must pass that suggestion's id.
  Future<PlaceDetails> resolve({
    required String placeId,
    required PlacesSession session,
  }) async {
    final result = await transport.details(
      placeId: placeId,
      sessionToken: session.token,
    );
    final data = result.data;
    final id = data['placeId'];
    final address = data['address'];
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    if (id is! String || id != placeId || address is! String) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    if (latitude is! num || longitude is! num) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    final attributions = data['attributions'] ?? const <Object?>[];
    if (attributions is! List || attributions.length > 20) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    try {
      return PlaceDetails(
        placeId: id,
        address: address,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        attributions: attributions.map(_attribution).toList(growable: false),
      );
    } on ArgumentError {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
  }

  PlaceSuggestion _suggestion(Object? entry) {
    if (entry is! Map) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    final placeId = entry['placeId'];
    final label = entry['label'];
    if (placeId is! String || label is! String) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    try {
      return PlaceSuggestion(placeId: placeId, label: label);
    } on ArgumentError {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
  }

  PlaceAttribution _attribution(Object? entry) {
    if (entry is! Map) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    final provider = entry['provider'];
    final uri = entry['uri'];
    if (provider is! String || uri is! String) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    try {
      return PlaceAttribution(provider: provider, uri: uri);
    } on ArgumentError {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
  }
}

/// User-safe message for a Places failure. Never includes provider details.
String placesFailureMessage(PlacesFailure failure) => switch (failure.code) {
  PlacesFailureCode.invalidInput => 'Check the search text and try again.',
  PlacesFailureCode.unconfigured =>
    'Place search is not configured yet. Enter the place manually.',
  PlacesFailureCode.rateLimited =>
    'Too many place searches right now. Try again shortly or enter it manually.',
  PlacesFailureCode.unavailable =>
    'Place search is unavailable. Enter the place manually.',
  PlacesFailureCode.invalidResponse =>
    'Place search returned an unexpected result. Enter the place manually.',
  PlacesFailureCode.sessionExpired =>
    'The place search expired. Search again or enter the place manually.',
  PlacesFailureCode.suggestionRequired =>
    'Search again and pick a fresh result, or enter the place manually.',
};

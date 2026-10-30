/// Validated Places reads for the app.
///
/// The repository checks the transport response against the shared contract
/// and maps anything unexpected to [PlacesFailureCode.invalidResponse]. It
/// keeps no query or address history and performs no automatic retries.
library;

import '../../../domain/phase2/common.dart';
import 'places_contract.dart';
import 'places_transport.dart';

class PlacesRepository {
  PlacesRepository({required this.transport});

  final PlacesTransport transport;

  Future<PlaceDetails> resolveAddress(String address) async {
    final query=address.trim();
    if (query.isEmpty || query.length>1000) throw const PlacesFailure(PlacesFailureCode.invalidInput);
    final resolver=transport;
    if (resolver is! AddressPlacesTransport) throw const PlacesFailure(PlacesFailureCode.unconfigured);
    final result=await (resolver as AddressPlacesTransport).address(address:query,sessionToken:PlacesSession.start().token);
    final place=_details(result.data);
    if (place.timezoneId==null || place.timezoneId!.trim().isEmpty) throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    return place;
  }

  Future<PlaceDetails> resolveCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    if (!latitude.isFinite || latitude.abs() > 90 ||
        !longitude.isFinite || longitude.abs() > 180) {
      throw const PlacesFailure(PlacesFailureCode.invalidInput);
    }
    final coordinateTransport = transport;
    if (coordinateTransport is! CoordinatePlacesTransport) {
      throw const PlacesFailure(PlacesFailureCode.unconfigured);
    }
    final result = await (coordinateTransport as CoordinatePlacesTransport).coordinates(
      latitude: latitude, longitude: longitude,
      sessionToken: PlacesSession.start().token,
    );
    final place = _details(result.data);
    if (place.latitude != latitude || place.longitude != longitude ||
        place.timezoneId == null || place.timezoneId!.trim().isEmpty) {
      throw const PlacesFailure(PlacesFailureCode.invalidResponse);
    }
    return place;
  }

  /// Resolve a saved address only when the provider returns one unambiguous
  /// match. Multiple matches stay in the picker for the user to choose.
  Future<PlaceDetails?> resolveSavedAddress(String address) async {
    final query = address.trim();
    if (query.length < 3 || query.length > placesMaxQueryLength) return null;
    final session = PlacesSession.start();
    final suggestions = await search(input: query, session: session);
    if (suggestions.length != 1) return null;
    final result = await resolve(placeId: suggestions.single.placeId, session: session);
    if (result.timezoneId == null || result.timezoneId!.trim().isEmpty) return null;
    return result;
  }

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
    return _details(result.data, expectedId: placeId);
  }

  PlaceDetails _details(Map<String, Object?> data, {String? expectedId}) {
    final id = data['placeId'];
    final address = data['address'];
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    if (id is! String || (expectedId != null && id != expectedId) || address is! String) {
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
      final components = data['postalAddress'];
      if (components != null && components is! Map) {
        throw const PlacesFailure(PlacesFailureCode.invalidResponse);
      }
      String? component(String key) {
        final value = components is Map ? components[key] : null;
        if (value == null) return null;
        if (value is! String || value.length > 300) {
          throw const PlacesFailure(PlacesFailureCode.invalidResponse);
        }
        return value;
      }

      return PlaceDetails(
        placeId: id,
        address: address,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        timezoneId: data['timezoneId'] is String
            ? data['timezoneId'] as String
            : null,
        postalAddress: components == null
            ? null
            : PostalAddress(
                line1: component('line1'),
                line2: component('line2'),
                city: component('city'),
                state: component('state'),
                postalCode: component('postalCode'),
                country: component('country'),
              ),
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
    'Address search is unavailable. Complete the address details and try again.',
  PlacesFailureCode.rateLimited =>
    'Too many address searches right now. Please try again shortly.',
  PlacesFailureCode.unavailable =>
    'Address search is unavailable. Complete the address details and try again.',
  PlacesFailureCode.invalidResponse =>
    'The address could not be checked. Complete its details and try again.',
  PlacesFailureCode.sessionExpired =>
    'The address search expired. Please try again.',
  PlacesFailureCode.suggestionRequired =>
    'Search again and choose a matching address.',
};

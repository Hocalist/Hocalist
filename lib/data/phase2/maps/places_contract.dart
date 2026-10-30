/// Places provider contract shared with the server transport.
///
/// The server-side transport (`supabase/functions/_shared/hocalist-places.ts`)
/// is the only component that talks to Google. This library defines the
/// request/response shapes, the session token, bounded values and typed
/// failures the app may rely on. It performs no network work itself and never
/// logs a query or an address.
library;

import 'dart:math';
import '../../../domain/phase2/common.dart';

import 'package:flutter/foundation.dart';

/// One device-location reading.
@immutable
class LocationReading {
  const LocationReading({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  String toString() => 'LocationReading([redacted])';
}

/// Device-location failure states the UI must handle.
enum LocationFailureCode { denied, deniedForever, serviceDisabled, unavailable }

class LocationFailure implements Exception {
  const LocationFailure(this.code);

  final LocationFailureCode code;

  @override
  String toString() => 'LocationFailure(${code.name})';
}

/// Foreground location reader. Implementations must request permission on
/// first use and must never start background tracking.
typedef LocationReader = Future<LocationReading> Function();

/// Stable failure codes mirrored from the server transport.
enum PlacesFailureCode {
  invalidInput,
  unconfigured,
  rateLimited,
  unavailable,
  invalidResponse,

  /// The server no longer accepts this search session. Start a fresh session
  /// and rerun the autocomplete before resolving a suggestion.
  sessionExpired,

  /// The details call referenced a place this session never received. Rerun
  /// the autocomplete with the current session, then resolve again.
  suggestionRequired,
}

/// Maps one `hocalist-places` HTTP failure to a typed failure.
///
/// [details] is the decoded endpoint body when available. Only the endpoint's
/// own error codes are read; an unknown body or status keeps the previous
/// status-based fallback. The endpoint never returns provider text.
PlacesFailure placesFailureFromEndpoint({int? status, Object? details}) {
  final code = details is Map ? details['error'] : null;
  switch (code) {
    case 'session_invalid':
    case 'session_expired':
    case 'session_exhausted':
      return const PlacesFailure(PlacesFailureCode.sessionExpired);
    case 'suggestion_required':
      return const PlacesFailure(PlacesFailureCode.suggestionRequired);
    case 'rate_limited':
      return const PlacesFailure(PlacesFailureCode.rateLimited);
    case 'unconfigured':
      return const PlacesFailure(PlacesFailureCode.unconfigured);
    case 'invalid_input':
      return const PlacesFailure(PlacesFailureCode.invalidInput);
  }
  if (status == 429) return const PlacesFailure(PlacesFailureCode.rateLimited);
  if (status == 400) return const PlacesFailure(PlacesFailureCode.invalidInput);
  if (status == 404) return const PlacesFailure(PlacesFailureCode.unconfigured);
  return const PlacesFailure(PlacesFailureCode.unavailable);
}

/// Typed Places failure. Never carries a provider body, query or address.
class PlacesFailure implements Exception {
  const PlacesFailure(this.code, {this.debugMessage});

  final PlacesFailureCode code;

  /// Developer-facing description. Must not contain user queries or addresses.
  final String? debugMessage;

  @override
  String toString() => 'PlacesFailure(${code.name})';
}

/// One autocomplete suggestion. [placeId] is the identity; [label] is display.
class PlaceSuggestion {
  PlaceSuggestion({required String placeId, required String label})
    : placeId = _requireText(placeId, 'placeId', 256),
      label = _requireText(label, 'label', 1000);

  final String placeId;
  final String label;

  @override
  String toString() => 'PlaceSuggestion($placeId)';
}

/// One resolved place with coordinates and provider attributions.
class PlaceDetails {
  PlaceDetails({
    required String placeId,
    required String address,
    required this.latitude,
    required this.longitude,
    this.timezoneId,
    this.postalAddress,
    List<PlaceAttribution> attributions = const [],
  }) : placeId = _requireText(placeId, 'placeId', 256),
       address = _requireText(address, 'address', 1000),
       attributions = List<PlaceAttribution>.unmodifiable(attributions) {
    if (!latitude.isFinite || latitude.abs() > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'must be -90..90');
    }
    if (!longitude.isFinite || longitude.abs() > 180) {
      throw ArgumentError.value(longitude, 'longitude', 'must be -180..180');
    }
  }

  final String placeId;
  final String address;
  final double latitude;
  final double longitude;
  final String? timezoneId;
  final PostalAddress? postalAddress;

  /// Provider attributions that must stay visible where the place is shown.
  final List<PlaceAttribution> attributions;

  @override
  String toString() => 'PlaceDetails($placeId)';
}

/// One required provider attribution (for example Google Maps).
class PlaceAttribution {
  PlaceAttribution({required String provider, required String uri})
    : provider = _requireText(provider, 'provider', 300),
      uri = _requireHttps(uri);

  final String provider;
  final String uri;

  @override
  String toString() => 'PlaceAttribution($provider)';
}

/// One search session. Autocomplete and the resolving details call must share
/// the same token; the token is discarded once details resolve or the session
/// expires client-side.
class PlacesSession {
  PlacesSession._(this.token, this._startedAt);

  factory PlacesSession.start({DateTime? now}) {
    return PlacesSession._(_uuidV4(), (now ?? DateTime.now()).toUtc());
  }

  /// Maximum client-side session age; a stale token starts a new session.
  static const Duration maxAge = Duration(minutes: 15);

  final String token;
  final DateTime _startedAt;

  bool isExpiredAt(DateTime now) => now.toUtc().difference(_startedAt) > maxAge;

  @override
  String toString() => 'PlacesSession([redacted])';
}

/// Client-side input bounds mirrored from the server transport.
const int placesMaxQueryLength = 200;

String _requireText(String value, String name, int max) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > max) {
    throw ArgumentError.value(value, name, 'must be 1..$max characters');
  }
  return trimmed;
}

String _requireHttps(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
    throw ArgumentError.value(uri, 'uri', 'must be an https URL');
  }
  return uri;
}

final Random _random = Random.secure();

/// RFC 4122 version 4 UUID, matching the server transport's token check.
String _uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
